# frozen_string_literal: true

module Entitlements
  class Backend
    class LDAP
      class Controller < Entitlements::Backend::BaseController
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
          @provider = Entitlements::Backend::LDAP::Provider.new(ldap: @ldap)
        end

        # Pre-fetch the existing group membership in each OU.
        #
        # Takes no arguments.
        #
        # Returns nothing. (Populates cache.)
        Contract C::None => C::Any
        def prefetch
          logger.debug "Pre-fetching group membership in #{group_name} (#{config['base']}) from LDAP"
          provider.read_all(config["base"])
        end

        # Validation routines.
        #
        # Takes no arguments.
        #
        # Returns nothing.
        Contract C::None => C::Any
        def validate
          return unless config["mirror"]
          Entitlements::Util::Mirror.validate_mirror!(group_name)
        end

        # Get count of changes.
        #
        # Takes no arguments.
        #
        # Returns an Integer.
        Contract C::None => Integer
        def change_count
          actions.size + (ou_needs_to_be_created? ? 1 : 0)
        end

        # Calculation routines.
        #
        # Takes no arguments.
        #
        # Returns nothing (populates @actions).
        Contract C::None => C::Any
        def calculate
          if ou_needs_to_be_created?
            logger.info "ADD #{config['base']}"
          end

          existing = provider.read_all(config["base"])
          proposed = Entitlements::Data::Groups::Calculated.read_all(group_name, config)

          # Calculate differences.
          added = (proposed - existing)
            .map { |i| Entitlements::Models::Action.new(i, nil, Entitlements::Data::Groups::Calculated.read(i), group_name) }
          removed = (existing - proposed)
            .map { |i| Entitlements::Models::Action.new(i, provider.read(i), nil, group_name) }
          changed = (existing & proposed)
            .reject { |i| provider.read(i).equals?(Entitlements::Data::Groups::Calculated.read(i)) }
            .map { |i| Entitlements::Models::Action.new(i, provider.read(i), Entitlements::Data::Groups::Calculated.read(i), group_name) }

          # Print the differences.
          print_differences(key: group_name, added: added, removed: removed, changed: changed)

          # Populate the actions
          @actions = [added, removed, changed].flatten.compact
        end

        # Pre-apply routines. For the LDAP provider this creates the OU if it does not exist,
        # and if "create_if_missing" has been set to true.
        #
        # Takes no arguments.
        #
        # Returns nothing.
        Contract C::None => C::Any
        def preapply
          return unless ou_needs_to_be_created?

          if ldap.upsert(dn: config["base"], attributes: {"objectClass" => "organizationalUnit"})
            logger.debug "APPLY: Creating #{config['base']}"
          else
            logger.warn "DID NOT APPLY: Changes not needed to #{config['base']}"
          end
        end

        # Apply changes.
        #
        # action - Action array.
        #
        # Returns nothing.
        Contract Entitlements::Models::Action => C::Any
        def apply(action)
          if action.updated.nil?
            logger.debug "APPLY: Deleting #{action.dn}"
            ldap.delete(action.dn)
          else
            override = Entitlements::Util::Override.override_hash_from_plugin(action.config["plugin"], action.updated, ldap) || {}
            if provider.upsert(action.updated, override)
              logger.debug "APPLY: Upserting #{action.dn}"
            else
              logger.warn "DID NOT APPLY: Changes not needed to #{action.dn}"
              logger.debug "Old: #{action.existing.inspect}"
              logger.debug "New: #{action.updated.inspect}"
            end
          end
        end

        # Validate configuration options.
        #
        # key  - String with the name of the group.
        # data - Hash with the configuration data.
        #
        # Returns nothing.
        Contract String, C::HashOf[String => C::Any] => nil
        def validate_config!(key, data)
          spec = COMMON_GROUP_CONFIG.merge({
            "base"               => { required: true, type: String },
            "create_if_missing"  => { required: false, type: [FalseClass, TrueClass]},
            "ldap_binddn"        => { required: true, type: String },
            "ldap_bindpw"        => { required: true, type: String },
            "ldap_ca_file"       => { required: false, type: String },
            "disable_ssl_verification" => { required: false, type: [FalseClass, TrueClass] },
            "ldap_uri"           => { required: true, type: String },
            "plugin"             => { required: false, type: Hash },
            "mirror"             => { required: false, type: String },
            "person_dn_format"   => { required: true, type: String }
          })
          text = "Group #{key.inspect}"
          Entitlements::Util::Util.validate_attr!(spec, data, text)
        end

        # ***********************************************************
        # Private methods for this backend go below.
        # ***********************************************************

        # Determine if the OU needs to be created.
        #
        # Takes no arguments.
        #
        # Returns an Array of Strings (DNs).
        Contract C::None => C::Bool
        def ou_needs_to_be_created?
          return false unless config["create_if_missing"]

          @ou_needs_to_be_created ||= begin
            if ldap.exists?(config["base"])
              logger.debug "OU create_if_missing: #{config['base']} already exists"
              :false
            else
              logger.debug "OU create_if_missing: #{config['base']} needs to be created"
              :true
            end
          end

          @ou_needs_to_be_created == :true
        end

        private

        attr_reader :ldap, :provider
      end
    end
  end
end
