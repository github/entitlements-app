# frozen_string_literal: true
# Interact with rules that are stored in a YAML file.

require "yaml"

module Entitlements
  class Data
    class Groups
      class Calculated
        class YAML < Entitlements::Data::Groups::Calculated::Base
          include ::Contracts::Core
          C = ::Contracts

          # Standard interface: Calculate the members of this group.
          #
          # Takes no arguments.
          #
          # Returns a Set[String] with DN's of the people in the group.
          Contract C::None => C::Or[:calculating, C::SetOf[Entitlements::Models::Person]]
          def members
            @members ||= begin
              Entitlements.logger.debug "Calculating members from #{filename}"
              members_from_rules(rules)
            end
          end

          # Standard interface: Get the description of this group.
          #
          # Takes no arguments.
          #
          # Returns a String with the group description, or "" if undefined.
          Contract C::None => String
          def description
            parsed_data.fetch("description", "")
          end

          # Standard interface: Get the schema version of this group.
          #
          # Takes no arguments.
          #
          # Returns a String with the schema version (semver), or "1.0.0" if undefined.
          Contract C::None => String
          def schema_version
            version = parsed_data.fetch("schema_version", "1.0.0")
            unless version.match?(/\A\d+\.\d+\.\d+\z/)
              raise "Invalid schema version format: #{version} - Expected format is 'MAJOR.MINOR.PATCH' - Examples: 1.2.3 or 10.0.0"
            end
            version
          end

          # Files can support modifiers that act independently of rules.
          # This returns the modifiers from the file as a hash.
          #
          # Takes no arguments.
          #
          # Returns Hash[<String>key => <Object>value]
          Contract C::None => C::HashOf[String => C::Any]
          def modifiers
            parsed_data.select { |k, _v| MODIFIERS.include?(k) }
          end

          private

          # Get a hash of the filters defined in the group.
          #
          # Takes no arguments.
          #
          # Returns a Hash[String => :all/:none/List of strings].
          Contract C::None => C::HashOf[String => C::Or[:all, :none, C::ArrayOf[String]]]
          def initialize_filters
            result = Entitlements::Data::Groups::Calculated.filters_default
            return result unless parsed_data.key?("filters")

            f = parsed_data["filters"]
            unless f.is_a?(Hash)
              raise ArgumentError, "For filters in #{filename}: expected Hash, got #{f.inspect}!"
            end

            f.each do |key, val|
              unless result.key?(key)
                raise ArgumentError, "Filter #{key} in #{filename} is invalid!"
              end

              values = if val.is_a?(String)
                         [val]
              elsif val.is_a?(Array)
                val
              else
                raise ArgumentError, "Value #{val.inspect} for #{key} in #{filename} is invalid!"
              end

              # Check for expiration
              values.reject! { |v| v.is_a?(Hash) && expired?(v["expiration"].to_s, filename) }
              values.map! { |v| v.is_a?(Hash) ? v.fetch("key") : v.strip }

              if values.size == 1 && (values.first == "all" || values.first == "none")
                result[key] = values.first.to_sym
              elsif values.size > 1 && (values.include?("all") || values.include?("none"))
                raise ArgumentError, "In #{filename}, #{key} cannot contain multiple entries when 'all' or 'none' is used!"
              elsif values.size == 0
                # This could happen if all of the specified filters were deleted due to expiration.
                # In that case make no changes so the default gets used.
                next
              else
                result[key] = values
              end
            end

            result
          end

          # Files can support metadata intended for consumption by things other than LDAP.
          # This returns the metadata from the file as a hash.
          #
          # Takes no arguments.
          #
          # Returns Hash[<String>key => <Object>value]
          Contract C::None => C::HashOf[String => C::Any]
          def initialize_metadata
            return {} unless parsed_data.key?("metadata")
            result = parsed_data["metadata"]

            unless result.is_a?(Hash)
              raise ArgumentError, "For metadata in #{filename}: expected Hash, got #{result.inspect}!"
            end

            result.each do |key, _|
              next if key.is_a?(String)
              raise ArgumentError, "For metadata in #{filename}: keys are expected to be strings, but #{key.inspect} is not!"
            end

            result
          end

          # Obtain the rule set from the YAML file and convert it to an object. Cache this the first
          # time it happens, because this code is going to be called once per person!
          #
          # Takes no arguments.
          #
          # Returns a Hash.
          Contract C::None => C::HashOf[String => C::Any]
          def rules
            @rules ||= begin
              rules_hash = parsed_data["rules"]
              unless rules_hash.is_a?(Hash)
                raise "Expected to find 'rules' as a Hash in #{filename}, but got #{rules_hash.class}!"
              end
              remove_expired_rules(rules_hash)
            end
          end

          # Remove expired rules from the rules hash.
          #
          # rules_hash - Hash of rules.
          #
          # Returns the updated hash that has no expired rules in it.
          Contract C::HashOf[String => C::Any] => C::HashOf[String => C::Any]
          def remove_expired_rules(rules_hash)
            if rules_hash.keys.size == 1
              if rules_hash.values.first.is_a?(Array)
                return { rules_hash.keys.first => rules_hash.values.first.map { |v| remove_expired_rules(v) }.reject { |h| h.empty? } }
              else
                return rules_hash
              end
            end

            expdate = rules_hash.delete("expiration")
            return {} if expired?(expdate, filename)
            rules_hash
          end

          # Return the parsed data from the file. This is called on demand and cached.
          #
          # Takes no arguments.
          #
          # Returns a Hash.
          # :nocov:
          Contract C::None => C::HashOf[String => C::Any]
          def parsed_data
            @parsed_data ||= if RubyVersionCheck.ruby_version2?
                               ::YAML.load(File.read(filename)).to_h
            else
              ::YAML.load(File.read(filename), permitted_classes: [Date]).to_h
            end
          end
          # :nocov:
        end
      end
    end
  end
end
