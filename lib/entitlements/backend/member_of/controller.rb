# frozen_string_literal: true

module Entitlements
  class Backend
    class MemberOf
      class Controller < Entitlements::Backend::BaseController
        # Controller priority and registration
        def self.priority
          20
        end

        register

        include ::Contracts::Core
        C = ::Contracts

        # Constructor. Generic constructor that takes a hash of configuration options.
        #
        # group_name - Name of the corresponding group in the entitlements configuration file.
        # config     - Optionally, a Hash of configuration information (configuration is referenced if empty).
        Contract String, C::Maybe[C::HashOf[String => C::Any]] => C::Any
        def initialize(group_name, config = nil)
          super

          @ldap = Entitlements::Service::LDAP.new_with_cache(
            addr: @config.fetch("ldap_uri"),
            binddn: @config.fetch("ldap_binddn"),
            bindpw: @config.fetch("ldap_bindpw"),
            ca_file: @config.fetch("ldap_ca_file", ENV["LDAP_CACERT"]),
            disable_ssl_verification: @config.fetch("ldap_disable_ssl_verification", false),
            person_dn_format: @config.fetch("person_dn_format")
          )
        end

        # Calculation routines.
        #
        # Takes no arguments.
        #
        # Returns nothing (populates @actions).
        Contract C::None => C::Any
        def calculate
          logger.debug "Calculating memberOf attributes for configured groups"

          # We need to update people attributes for each group that is calculated and tagged with an
          # attribute that needs to be updated.
          cleared = Set.new

          relevant_groups = Entitlements::Data::Groups::Calculated.all_groups.select do |ou_key, _|
            config["ou"].include?(ou_key)
          end

          unless relevant_groups.any?
            raise "memberOf emulator found no OUs matching: #{config['ou'].join(', ')}"
          end

          attribute = config["memberof_attribute"]

          relevant_groups.each do |ou_key, data|
            if cleared.add?(attribute)
              Entitlements.cache[:people_obj].read.each do |uid, _person|
                Entitlements.cache[:people_obj].read(uid)[attribute] = []
              end
            end

            data[:groups].each do |group_dn, group_data|
              group_data.member_strings.each do |member|
                Entitlements.cache[:people_obj].read(member).add(attribute, group_dn)
              end
            end
          end

          # Now to populate the actions we have to see which persons have changed attributes.
          @actions = Entitlements.cache[:people_obj].read
            .reject { |_uid, person| person.attribute_changes.empty? }
            .map do |person_uid, person|
              print_differences(person)

              Entitlements::Models::Action.new(
                person_uid,
                :none, # Convention, since entitlements doesn't (yet) create people
                person,
                group_name
              )
            end
        end

        # Apply changes.
        #
        # action - Action array.
        #
        # Returns nothing.
        Contract Entitlements::Models::Action => C::Any
        def apply(action)
          person = action.updated
          changes = person.attribute_changes
          changes.each do |attrib, val|
            if val.nil?
              logger.debug "APPLY: Delete #{attrib} from #{person.uid}"
            else
              logger.debug "APPLY: Upsert #{attrib} to #{person.uid}"
            end
          end

          person_dn = ldap.person_dn_format.gsub("%KEY%", person.uid)
          unless ldap.modify(person_dn, changes)
            logger.warn "DID NOT APPLY: Changes to #{person.uid} failed!"
            raise "LDAP modify error on #{person_dn}!"
          end
        end

        # Print difference array. The difference printer is a bit different for people rather than
        # groups, since groups really only had a couple attributes of interest but were spread across
        # multiple OUs, whereas people exist in one OU but have multiple attributes of interest.
        #
        # person - An Entitlements::Models::Person object.
        #
        # Returns nothing (this just prints to logger).
        Contract Entitlements::Models::Person => C::Any
        def print_differences(person)
          changes = person.attribute_changes
          return if changes.empty?

          plural = changes.size == 1 ? "" : "s"
          logger.info "Person #{person.uid} attribute change#{plural}:"

          changes.sort.to_h.each do |attrib, val|
            orig = person.original(attrib)
            if orig.nil?
              # Added attribute
              if val.is_a?(Array)
                logger.info ". ADD attribute #{attrib}:"
                val.each { |item| logger.info ".   + #{item}" }
              else
                logger.info ". ADD attribute #{attrib}: #{val.inspect}"
              end
            elsif val.nil?
              # Removed attribute
              if orig.is_a?(Array)
                word = orig.size == 1 ? "entry" : "entries"
                logger.info ". REMOVE attribute #{attrib}: #{orig.size} #{word}"
              else
                logger.info ". REMOVE attribute #{attrib}: #{orig.inspect}"
              end
            else
              # Modified attribute
              logger.info ". MODIFY attribute #{attrib}:"
              if val.is_a?(String) && orig.is_a?(String)
                # Simple string change
                logger.info ".  - #{orig.inspect}"
                logger.info ".  + #{val.inspect}"
              elsif val.is_a?(Array) && orig.is_a?(Array)
                # Array difference
                added = Set.new(val - orig)
                removed = Set.new(orig - val)
                combined = (added.to_a + removed.to_a)
                combined.sort.each do |item|
                  sign = added.member?(item) ? "+" : "-"
                  logger.info ".  #{sign} #{item.inspect}"
                end
              else
                # Data type mismatch is unexpected, so don't try to handle every possible case.
                # This should only happen if LDAP schema changes. Just dump out the data structures.
                logger.info ".  - (#{orig.class})"
                logger.info ".  + #{val.inspect}"
              end
            end
          end

          # Return nil to satisfy contract
          nil
        end

        private

        attr_reader :ldap

        # Validate configuration options.
        #
        # key  - String with the name of the group.
        # data - Hash with the configuration data.
        #
        # Returns nothing.
        # :nocov:
        Contract String, C::HashOf[String => C::Any] => nil
        def validate_config!(key, data)
          spec = COMMON_GROUP_CONFIG.merge({
            "ldap_binddn"        => { required: true, type: String },
            "ldap_bindpw"        => { required: true, type: String },
            "ldap_ca_file"       => { required: false, type: String },
            "ldap_uri"           => { required: true, type: String },
            "disable_ssl_verification" => { required: false, type: [FalseClass, TrueClass] },
            "memberof_attribute" => { required: true, type: String },
            "person_dn_format"   => { required: true, type: String },
            "ou"                 => { required: true, type: Array }
          })
          text = "Group #{key.inspect}"
          Entitlements::Util::Util.validate_attr!(spec, data, text)
        end
        # :nocov:
      end
    end
  end
end
