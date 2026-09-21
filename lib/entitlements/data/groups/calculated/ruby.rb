# frozen_string_literal: true
# Interact with rules that are stored as ruby code.

module Entitlements
  class Data
    class Groups
      class Calculated
        class Ruby < Entitlements::Data::Groups::Calculated::Base
          include ::Contracts::Core
          C = ::Contracts

          # Standard interface: Calculate the members of this group.
          #
          # Takes no arguments.
          #
          # Returns a Set[Entitlements::Models::Person] with DN's of the people in the group.
          Contract C::None => C::SetOf[Entitlements::Models::Person]
          def members
            @members ||= begin
              Entitlements.logger.debug "Calculating members from #{filename}"
              result = rule_obj.members

              # Since this is user-written code not subject to contracts, do some basic
              # format checking of the result, and standardize the output.
              unless result.is_a?(Set)
                raise "Expected Set[String|Entitlements::Models::Person] from #{ruby_class_name}.members, got #{result.class}!"
              end

              cleaned_set = result.map do |item|
                if item.is_a?(String)
                  begin
                    Entitlements.cache[:people_obj].read.fetch(item)
                  rescue KeyError => exc
                    raise_rule_exception(exc)
                  end
                elsif item.is_a?(Entitlements::Models::Person)
                  item
                else
                  raise "In #{ruby_class_name}.members, expected String or Person but got #{item.inspect}"
                end
              end

              # All good, return the result.
              Set.new(cleaned_set)
            end
          end

          # Standard interface: Get the description of this group.
          #
          # Takes no arguments.
          #
          # Returns a String with the group description, or "" if undefined.
          Contract C::None => String
          def description
            result = rule_obj.description
            return result if result.is_a?(String)
            raise "Expected String from #{ruby_class_name}.description, got #{result.class}!"
          end

          private

          # Get a hash of the filters defined in the group.
          #
          # Takes no arguments.
          #
          # Returns a Hash[String => :all/:none/List of strings].
          Contract C::None => C::HashOf[String => C::Or[:all, :none, C::ArrayOf[String]]]
          def initialize_filters
            rule_obj.filters
          end

          # Files can support metadata intended for consumption by things other than LDAP.
          # This returns the metadata from the file as a hash.
          #
          # Takes no arguments.
          #
          # Returns Hash[<String>key => <Object>value]
          Contract C::None => C::HashOf[String => C::Any]
          def initialize_metadata
            return {} unless rule_obj.respond_to?(:metadata)

            result = rule_obj.metadata

            unless result.is_a?(Hash)
              raise ArgumentError, "For metadata in #{filename}: expected Hash, got #{result.inspect}!"
            end

            result.each do |key, _|
              next if key.is_a?(String)
              raise ArgumentError, "For metadata in #{filename}: keys are expected to be strings, but #{key.inspect} is not!"
            end

            result
          end

          # Instantiate the object exactly once, on demand. Cache it for later.
          #
          # Takes no arguments.
          #
          # Returns an object.
          Contract C::None => Object
          def rule_obj
            @rule_obj ||= begin
              require filename
              clazz = Kernel.const_get(ruby_class_name)
              clazz.new
            end
          end

          # Raise an exception which adds in the offending class name and filename (which
          # is a user-defined entitlement that gave rise to a problem).
          #
          # exc - An Exception that is to be raised.
          #
          # Returns nothing (raises the exception after logging).
          Contract Exception => nil
          def raise_rule_exception(exc)
            Entitlements.logger.fatal "#{exc.class} when processing #{ruby_class_name}!"
            raise exc
          end

          # Turn the filename into a ruby class name. We care about the name of the last
          # directory, and the name of the file itself. Convert these into CamelCase for
          # the ruby class.
          #
          # Takes no arguments.
          #
          # Returns a String with the class name.
          Contract C::None => String
          def ruby_class_name
            ["Entitlements", "Rule", ou, cn].map { |x| camelize(x) }.join("::")
          end
        end
      end
    end
  end
end
