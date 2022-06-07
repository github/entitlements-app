# frozen_string_literal: true

require "json"

module Entitlements
  class Data
    class People
      class Combined
        include ::Contracts::Core
        C = ::Contracts

        PARAMETERS = {
          "operator"   => { required: true, type: String },
          "components" => { required: true, type: Array },
        }

        # Fingerprint for the object based on unique parameters from the group configuration. If the fingerprint
        # matches the same object should be re-used. This will raise an error if insufficient configuration is
        # given.
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns a String with the "fingerprint" for this configuration.
        Contract C::HashOf[String => C::Any] => String
        def self.fingerprint(config)
          # Fingerprint of the combined provider is the fingerprint of each constitutent provider. Then serialize
          # to JSON to account for the and/or operator that is part of this configuration. Note: this method might
          # end up being called recursively depending on the complexity of the combined configuration.
          fingerprints = config["components"].map do |component|
            Entitlements::Data::People.class_for_config(component).fingerprint(component.fetch("config"))
          end

          JSON.generate(config.fetch("operator") => fingerprints)
        end

        # Construct this object based on parameters in a group configuration. This is the direct translation
        # between the Entitlements configuration file (which is always a Hash with configuration values) and
        # the object constructed from this class (which can have whatever structure makes sense).
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns Entitlements::Data::People::Combined object.
        # :nocov:
        Contract C::HashOf[String => C::Any] => Entitlements::Data::People::Combined
        def self.new_from_config(config)
          new(
            operator: config.fetch("operator"),
            components: config.fetch("components")
          )
        end
        # :nocov:

        # Validate configuration options.
        #
        # key    - String with the name of the data source.
        # config - Hash with the configuration data.
        #
        # Returns nothing.
        Contract String, C::HashOf[String => C::Any] => nil
        def self.validate_config!(key, config)
          text = "Combined people configuration for data source #{key.inspect}"
          Entitlements::Util::Util.validate_attr!(PARAMETERS, config, text)

          unless %w[and or].include?(config["operator"])
            raise ArgumentError, "In #{key}, expected 'operator' to be either 'and' or 'or', not #{config['operator'].inspect}!"
          end

          component_spec = {
            "config" => { required: true, type: Hash },
            "name"   => { required: false, type: String },
            "type"   => { required: true, type: String },
          }

          if config["components"].empty?
            raise ArgumentError, "In #{key}, the array of components cannot be empty!"
          end

          config["components"].each do |component|
            if component.is_a?(Hash)
              component_name = component.fetch("name", component.inspect)
              component_text = "Combined people configuration #{key.inspect} component #{component_name}"
              Entitlements::Util::Util.validate_attr!(component_spec, component, component_text)
              clazz = Entitlements::Data::People.class_for_config(component)
              clazz.validate_config!("#{key}:#{component_name}", component.fetch("config"))
            elsif component.is_a?(String)
              if Entitlements.config.fetch("people", {}).fetch(component, nil)
                resolved_component = Entitlements.config["people"][component]
                clazz = Entitlements::Data::People.class_for_config(resolved_component)
                clazz.validate_config!(component, resolved_component.fetch("config"))
              else
                raise ArgumentError, "In #{key}, reference to invalid component #{component.inspect}!"
              end
            else
              raise ArgumentError, "In #{key}, expected array of hashes/strings but got #{component.inspect}!"
            end
          end

          nil
        end

        # Constructor.
        #
        Contract C::KeywordArgs[
          operator: String,
          components: C::ArrayOf[C::HashOf[String => C::Any]]
        ] => C::Any
        def initialize(operator:, components:)
          @combined = { operator: operator }
          @combined[:components] = components.map do |component|
            clazz = Entitlements::Data::People.class_for_config(component)
            clazz.new_from_config(component["config"])
          end
          @people = nil
        end

        # Read in the people from a combined provider. Cache result for later access.
        #
        # uid - Optionally a uid to return. If not specified, returns the entire hash.
        #
        # Returns Hash of { uid => Entitlements::Models::Person } or one Entitlements::Models::Person.
        Contract C::Maybe[String] => C::Or[Entitlements::Models::Person, C::HashOf[String => Entitlements::Models::Person]]
        def read(uid = nil)
          @people ||= read_entire_hash
          return @people unless uid

          @people_downcase ||= @people.map { |people_uid, _data| [people_uid.downcase, people_uid] }.to_h
          unless @people_downcase.key?(uid.downcase)
            raise Entitlements::Data::People::NoSuchPersonError, "read(#{uid.inspect}) matched no known person"
          end

          @people[@people_downcase[uid.downcase]]
        end

        private

        # Read an entire hash from the combined data source.
        #
        # Takes no arguments.
        #
        # Returns Hash of { uid => Entitlements::Models::Person }.
        Contract C::None => C::HashOf[String => Entitlements::Models::Person]
        def read_entire_hash
          # @combined[:operator] is "or" or "and". Call the "read" method on each component and then assemble the
          # results according to the specified logic. When a user is seen more than once, deconflict by using the *first*
          # constructed person model that we have seen.
          data = @combined[:components].map { |component| component.read }

          result = {}
          data.each do |data_hash|
            data_hash.each do |user, user_data|
              result[user] ||= user_data
            end
          end

          if @combined[:operator] == "and"
            users = Set.new(common_keys(data))
            result.select! { |k, _| users.member?(k) }
          end

          result
        end

        # Given an arbitrary number of hashes, return the keys that are common in all of them.
        # (hash1_keys & hash2_keys & hash3_keys)
        #
        # hashes - An array of hashes in which to find common keys.
        #
        # Returns an array of common elements.
        Contract C::ArrayOf[Hash] => C::SetOf[C::Any]
        def common_keys(hashes)
          return Set.new if hashes.empty?

          hash1 = hashes.shift
          result = Set.new(hash1.keys)
          hashes.each { |h| result = result & h.keys }
          result
        end

        # Given an arbitrary number of hashes, return all keys seen in any of them.
        # (hash1_keys | hash2_keys | hash3_keys)
        #
        # arrays - An array of arrays with elements in which to find any elements.
        #
        # Returns an array of all elements.
        Contract C::ArrayOf[Hash] => C::SetOf[C::Any]
        def all_keys(hashes)
          return Set.new if hashes.empty?

          hash1 = hashes.shift
          result = Set.new(hash1.keys)
          hashes.each { |h| result.merge(h.keys) }
          result
        end
      end
    end
  end
end
