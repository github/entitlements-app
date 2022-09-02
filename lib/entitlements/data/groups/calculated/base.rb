# frozen_string_literal: true
# Base class to interact with rules stored in some kind of file or directory structure.

require_relative "rules/base"
require_relative "rules/group"
require_relative "rules/username"

require_relative "filters/base"
require_relative "filters/member_of_group"

require_relative "modifiers/expiration"

module Entitlements
  class Data
    class Groups
      class Calculated
        class Base
          include ::Contracts::Core
          C = ::Contracts

          ALIAS_METHODS = {
            "entitlements_group" => "group"
          }

          MAX_MODIFIER_ITERATIONS = 100

          MODIFIERS = %w[
            expiration
          ]

          attr_reader :filename, :filters, :metadata

          # ---------------------------------------------
          # Interface which all rule sets must implement.
          # ---------------------------------------------

          # Get the list of the group members found by applying the rule set.
          #
          # Takes no arguments.
          #
          # Returns Set[Entitlements::Models::Person] of all matching members.
          Contract C::None => C::SetOf[Entitlements::Models::Person]
          def members
            # :nocov:
            raise "Must be implemented in child class"
            # :nocov:
          end

          # Get the description of the group.
          #
          # Takes no arguments.
          #
          # Returns a String.
          Contract C::None => String
          def description
            # :nocov:
            raise "Must be implemented in child class"
            # :nocov:
          end

          # Stub modifiers. Override in child class if they are supported for a given entitlement type.
          #
          # Takes no arguments.
          #
          # Returns Hash[<String>key => <Object>value]
          # :nocov:
          Contract C::None => C::HashOf[String => C::Any]
          def modifiers
            {}
          end
          # :nocov:

          # ---------------------------------------------
          # Helper.
          # ---------------------------------------------

          # Constructor.
          #
          # filename - Filename with the ruleset.
          # options  - An optional hash of additional options.
          Contract C::KeywordArgs[
            filename: String,
            config: C::Maybe[C::HashOf[String => C::Any]],
            options: C::Optional[C::HashOf[Symbol => C::Any]]
          ] => C::Any
          def initialize(filename:, config: nil, options: {})
            @filename = filename
            @config = config
            @options = options
            @metadata = initialize_metadata
            @filters = initialize_filters
          end

          # Log a fatal message to logger and then exit with the same error message.
          #
          # message - String with the message to log and raise.
          #
          # Returns nothing.
          Contract String => C::None
          def fatal_message(message)
            Entitlements.logger.fatal(message)
            raise RuntimeError, message
          end

          # Members of the group with filters applied.
          #
          # members_in - Optionally a set of Entitlements::Models::Person with the currently calculated member set.
          #
          # Returns Set[Entitlements::Models::Person] of all matching members.
          Contract C::None => C::Or[:calculating, C::SetOf[Entitlements::Models::Person]]
          def filtered_members
            return :calculating if members == :calculating

            # Start with the set of all members that are calculated. For each filter that is not set
            # to the special value :all, run the filter to remove progressively more members.
            @filtered_members ||= begin
              result = members.dup
              filters.reject { |_, filter_val| filter_val == :all }.each do |filter_name, filter_val|
                filter_cfg = Entitlements::Data::Groups::Calculated.filters_index[filter_name]
                clazz = filter_cfg.fetch(:class)
                obj = clazz.new(filter: filter_val, config: filter_cfg.fetch(:config, {}))
                # If excluded_paths is set, ignore any of those excluded paths
                unless filter_cfg[:config]["excluded_paths"].nil?
                  # if the filename is not in any of the excluded paths, filter it
                  unless filter_cfg[:config]["excluded_paths"].any? { |excluded_path| filename.include?(excluded_path) }
                    result.reject! { |member| obj.filtered?(member) }
                  end
                end

                # if included_paths is set, filter only files at those included paths
                unless filter_cfg[:config]["included_paths"].nil?
                  # if the filename is in any of the included paths, filter it
                  if filter_cfg[:config]["included_paths"].any? { |included_path| filename.include?(included_path) }
                    result.reject! { |member| obj.filtered?(member) }
                  end
                end

                # if neither included_paths nor excluded_paths are set, filter normally
                if filter_cfg[:config]["included_paths"].nil? and filter_cfg[:config]["excluded_paths"].nil?
                  result.reject! { |member| obj.filtered?(member) }
                end
              end
              result
            end
          end

          # Members of the group with modifiers applied.
          #
          # Takes no arguments.
          #
          # Returns Set[Entitlements::Models::Person] of all matching members.
          Contract C::None => C::Or[:calculating, C::SetOf[Entitlements::Models::Person]]
          def modified_members
            return :calculating if members == :calculating
            @modified_members ||= apply_modifiers(members)
          end

          # Members of the group with modifiers and filters applied (in that order).
          #
          # members_in - Optionally a set of Entitlements::Models::Person with the currently calculated member set.
          #
          # Returns Set[Entitlements::Models::Person] of all matching members.
          Contract C::None => C::Or[:calculating, C::SetOf[Entitlements::Models::Person]]
          def modified_filtered_members
            return :calculating if filtered_members == :calculating
            @modified_filtered_members ||= apply_modifiers(filtered_members)
          end

          private

          attr_reader :config, :options

          # Common method that takes a given list of members and applies the modifiers.
          # Used to calculated `modified_members` and `modified_filtered_members`.
          #
          # member_set - Set of Entitlements::Models::Person
          #
          # Returns a set of Entitlements::Models::Person
          Contract C::SetOf[Entitlements::Models::Person] => C::SetOf[Entitlements::Models::Person]
          def apply_modifiers(member_set)
            result = member_set.dup

            modifier_objects = modifiers_constant.map do |m|
              if modifiers.key?(m)
                modifier_class = "Entitlements::Data::Groups::Calculated::Modifiers::" + Entitlements::Util::Util.camelize(m)
                clazz = Kernel.const_get(modifier_class)
                clazz.new(rs: self, config: modifiers.fetch(m))
              else
                nil
              end
            end.compact

            converged = false
            1.upto(MAX_MODIFIER_ITERATIONS) do
              unless modifier_objects.select { |modifier| modifier.modify(result) }.any?
                converged = true
                break
              end
            end

            unless converged
              raise "Modifiers for filename=#{filename} failed to converge after #{MAX_MODIFIER_ITERATIONS} iterations"
            end

            result
          end

          # Determine if an entry is expired or not. Return true if expired, false if not.
          #
          # expiration - A String (should have YYYY-MM-DD), or nil.
          # context    - A String (usually a filename) to provide context if there's an error.
          #
          # Returns true if expired, false if not expired.
          Contract C::Or[nil, String], String => C::Or[nil, C::Bool]
          def expired?(expiration, context)
            return false if Entitlements.config.fetch("ignore_expirations", false)
            return false if expiration.nil? || expiration.strip.empty?
            if expiration =~ /\A(\d{4})-(\d{2})-(\d{2})\z/
              year, month, day = Regexp.last_match(1).to_i, Regexp.last_match(2).to_i, Regexp.last_match(3).to_i
              return Time.utc(year, month, day, 0, 0, 0) <= Time.now.utc
            end
            message = "Invalid expiration date #{expiration.inspect} in #{context} (expected format: YYYY-MM-DD)"
            raise ArgumentError, message
          end

          # Wrapper method around `members_from_rules` that calls the method and caches the result.
          #
          # rule - A Hash of rules (see "rules" stub below).
          #
          # Returns Set[Entitlements::Models::Person].
          Contract C::HashOf[String => C::Any] => C::Or[:calculating, C::SetOf[Entitlements::Models::Person]]
          def members_from_rules(rule)
            Entitlements.cache[:calculated] ||= {}
            Entitlements.cache[:calculated][rou] ||= {}

            # Already calculated it? Just return it.
            return Entitlements.cache[:calculated][rou][cn] if Entitlements.cache[:calculated][rou][cn]

            # Add it to the list of things we are currently calculating so we can detect and report
            # on circular dependencies later.
            Entitlements.cache[:calculated][rou][cn] = :calculating
            Entitlements.cache[:dependencies] ||= []
            Entitlements.cache[:dependencies] << "#{rou}/#{cn}"

            # Actually calculate it.
            Entitlements.cache[:calculated][rou][cn] = _members_from_rules(rule)

            # This should be the last item on the dependencies array, so pop it off.
            unless Entitlements.cache[:dependencies].last == "#{rou}/#{cn}"
              # This would be a bug
              # :nocov:
              raise "Error: Unexpected last item in dependencies: expected #{rou}/#{cn} got #{Entitlements.cache[:dependencies].inspect}"
              # :nocov:
            end
            Entitlements.cache[:dependencies].pop

            # Return the calculated value.
            Entitlements.cache[:calculated][rou][cn]
          end

          # Apply logic in a hash of rules, where necessary making calls to the appropriate function
          # in our rules toolbox.
          #
          # rule - A Hash of rules (see "rules" stub below).
          #
          # Returns Set[Entitlements::Models::Person].
          Contract C::HashOf[String => C::Any] => C::SetOf[Entitlements::Models::Person]
          def _members_from_rules(rule)
            # Empty rule => error.
            if rule.keys.empty?
              raise "Rule Error: Rule had no keys in #{filename}!"
            end

            # The rule should only have one { key => Object }.
            unless rule.keys.size == 1
              raise "Rule Error: Rule had multiple keys #{rule.inspect} in #{filename}!"
            end

            # Always => false is special. It returns nothing.
            if rule["always"] == false
              return Set.new
            end

            # Go through the rule. Each key is one of the following:
            #  - "or": An array of conditions; if any is true, this rule is true
            #  - "and": An array of conditions; if all are true, the rule is true
            #  - "not": Takes a hash (can also be "and" / "or"); if it's true, the rule is false
            #  - anything else: Must correspond to something in "rules"
            function = function_for(rule.first.first)
            obj = rule.first.last

            return handle_or(obj) if function == "or"
            return handle_and(obj) if function == "and"
            return handle_not(obj) if function == "not"

            unless allowed_methods.member?(function)
              Entitlements.logger.fatal "The method #{function.inspect} is not permitted in #{filename}!"
              raise "Rule Error: #{function} is not a valid function in #{filename}!"
            end

            clazz = Entitlements::Data::Groups::Calculated.rules_index[function]
            clazz.matches(value: obj, filename: filename, options: options)
          end

          # Obtain the rule set from the YAML file and convert it to an object. Cache this the first
          # time it happens, because this code is going to be called once per person!
          #
          # Takes no arguments.
          #
          # Returns a Hash.
          Contract C::None => C::HashOf[String => C::Any]
          def rules
            # :nocov:
            raise "Must be implemented in child class"
            # :nocov:
          end

          # Handle boolean OR logic.
          # Do not enforce contract here since this is user-provided logic and we want a friendlier message.
          #
          # rule - (Hopefully) Array[Hash[String => obj]]
          #
          # Returns C::SetOf[Entitlements::Models::Person] from a recursive call.
          def handle_or(rule)
            ensure_type!("or", rule, Array)
            result = Set.new
            rule.each do |item|
              ensure_type!("or", item, Hash)
              item_result = _members_from_rules(item)
              result.merge item_result
            end
            result
          end

          # Handle boolean AND logic.
          # Do not enforce contract here since this is user-provided logic and we want a friendlier message.
          #
          # rule - (Hopefully) Array[Hash[String => obj]]
          #
          # Returns C::SetOf[Entitlements::Models::Person] from a recursive call.
          def handle_and(rule)
            ensure_type!("and", rule, Array)
            return result unless rule.any?

            first_rule = rule.shift
            ensure_type!("and", first_rule, Hash)
            result = _members_from_rules(first_rule)

            rule.each do |item|
              ensure_type!("and", item, Hash)
              item_result = _members_from_rules(item)
              result = result & item_result
            end

            result
          end

          # Handle boolean NOT logic.
          # Do not enforce contract here since this is user-provided logic and we want a friendlier message.
          #
          # rule - (Hopefully) Hash[String => obj]
          #
          # Returns C::SetOf[Entitlements::Models::Person] from a recursive call.
          def handle_not(rule)
            ensure_type!("not", rule, Hash)
            all_people = Set.new(Entitlements.cache[:people_obj].read.map { |_, obj| obj })
            matches = _members_from_rules(rule)
            all_people - matches
          end

          # ensure_type!: Force the incoming argument to be the indicated type. Not handled
          # via the contracts mechanism so a friendlier error is printed, since it's
          # user code that would break this.
          #
          # function - A String with the function name (e.g. "or" or some rule)
          # obj      - The object that's supposed to be the indicated type
          # type     - The type.
          #
          # Returns nothing, but raises an error if the type doesn't match.
          Contract String, C::Any, C::Any => nil
          def ensure_type!(function, obj, type)
            return if obj.is_a?(type)
            raise "Invalid type: in #{filename}, expected #{function.inspect} to be a #{type} but got #{obj.inspect}!"
          end

          # Convert a string into CamelCase.
          #
          # str - The string that needs to be converted to CamelCase.
          #
          # Returns a String in CamelCase.
          Contract String => String
          def camelize(str)
            Entitlements::Util::Util.camelize(str)
          end

          # Determine the ou from the filename (it's the last directory name).
          #
          # Takes no arguments.
          #
          # Returns a String with the name of the ou.
          Contract C::None => String
          def ou
            File.basename(File.dirname(filename))
          end

          # Determine the relatiive ou from the filename (relative to the config root)
          #
          # Takes no arguments.
          #
          # Returns a String with the name of the ou.
          Contract C::None => String
          def rou
            File.expand_path(File.dirname(filename)).gsub("#{Entitlements.config_path}/", "").gsub(/^\//, "").gsub(/\//, "/")
          end

          # Determine the cn from the filename (it's the filename without the extension).
          #
          # Takes no arguments.
          #
          # Returns a String with the name of the cn.
          Contract C::None => String
          def cn
            File.basename(filename).sub(/\.[^\.]+\z/, "")
          end

          # Get the permitted methods for this ou. Defaults to whitelisted methods from base class which
          # allows any supported method, but can be locked down further by setting `allowed_methods`
          # in the configuration for the ou or overriding whitelisted methods for the class.
          #
          # Takes no arguments.
          #
          # Returns a Set with the permitted methods.
          Contract C::None => C::SetOf[String]
          def allowed_methods
            @allowed_methods ||= begin
              if config.is_a?(Hash) && config["allowed_methods"]
                unless config["allowed_methods"].is_a?(Array)
                  raise ArgumentError, "allowed_methods must be an Array in #{filename}!"
                end
                Set.new(whitelisted_methods.to_a & config["allowed_methods"])
              else
                whitelisted_methods
              end
            end
          end

          # Get the method for a given function. Returns the underlying function if the entry is an
          # alias, or else returns what was entered. The caller is responsible to validate that the
          # function is valid and whitelisted.
          #
          # function_in - String with the function name from the definition.
          #
          # Returns the underlying function name if aliased, or else what was entered.
          Contract String => String
          def function_for(function_in)
            ALIAS_METHODS[function_in] || function_in
          end

          # Get the whitelisted methods. This is just set to the constant in the base class, but
          # is defined as a method so it can be overridden in the child class if needed.
          #
          # Takes no arguments.
          #
          # Returns an Set of Strings with allowed methods.
          Contract C::None => C::SetOf[String]
          def whitelisted_methods
            Set.new(Entitlements::Data::Groups::Calculated.rules_index.keys)
          end

          # Get the value of the modifiers constant. This is here so it can be stubbed
          # in CI testing more easily.
          def modifiers_constant
            MODIFIERS
          end
        end
      end
    end
  end
end
