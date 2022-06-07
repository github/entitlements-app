# frozen_string_literal: true
# Interact with rules that are stored in a simplified text file.

require "yaml"
require_relative "../../../util/util"

module Entitlements
  class Data
    class Groups
      class Calculated
        class Text < Entitlements::Data::Groups::Calculated::Base
          include ::Contracts::Core
          C = ::Contracts

          SEMICOLON_PREDICATES = %w[expiration]

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
            return "" unless parsed_data.key?("description")

            if parsed_data["description"]["!="].any?
              fatal_message("The description cannot use '!=' operator in #{filename}!")
            end

            unless parsed_data["description"]["="].size == 1
              fatal_message("The description key is duplicated in #{filename}!")
            end

            parsed_data["description"]["="].first.fetch(:key)
          end

          # Files can support modifiers that act independently of rules.
          # This returns the modifiers from the file as a hash.
          #
          # Takes no arguments.
          #
          # Returns Hash[<String>key => <Object>value]
          Contract C::None => C::HashOf[String => C::Any]
          def modifiers
            parse_with_prefix("modifier_")
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

            parsed_data.each do |raw_key, val|
              if raw_key == "filter_"
                fatal_message("In #{filename}, cannot have a key named \"filter_\"!")
              end

              next unless raw_key.start_with?("filter_")
              key = raw_key.sub(/\Afilter_/, "")

              unless result.key?(key)
                fatal_message("In #{filename}, the key #{raw_key} is invalid!")
              end

              if val["!="].any?
                fatal_message("The filter #{key} cannot use '!=' operator in #{filename}!")
              end

              values = val["="].reject { |v| expired?(v[:expiration], filename) }.map { |v| v[:key].strip }
              if values.size == 1 && (values.first == "all" || values.first == "none")
                result[key] = values.first.to_sym
              elsif values.size > 1 && (values.include?("all") || values.include?("none"))
                fatal_message("In #{filename}, #{raw_key} cannot contain multiple entries when 'all' or 'none' is used!")
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
            parse_with_prefix("metadata_")
          end

          # Metadata and modifiers are parsed with nearly identical logic. In DRY spirit, use
          # a single parsing method.
          #
          # prefix - String with the prefix expected for the key.
          #
          # Returns Hash[<String>key => <Object>value]
          Contract String => C::HashOf[String => C::Any]
          def parse_with_prefix(prefix)
            result = {}
            parsed_data.each do |raw_key, val|
              if raw_key == "#{prefix}"
                raise "In #{filename}, cannot have a key named \"#{prefix}\"!"
              end

              next unless raw_key.start_with?(prefix)
              key = raw_key.sub(/\A#{prefix}/, "")

              if val["!="].any?
                fatal_message("The key #{raw_key} cannot use '!=' operator in #{filename}!")
              end

              unless val["="].size == 1
                fatal_message("In #{filename}, the key #{raw_key} is repeated!")
              end

              unless val["="].first.keys == [:key]
                settings = (val["="].first.keys - [:key]).map { |i| i.to_s.inspect }.join(",")
                fatal_message("In #{filename}, the key #{raw_key} cannot have additional setting(s) #{settings}!")
              end

              result[key] = val["="].first.fetch(:key)
            end
            result
          end

          # Obtain the rule set from the content of the file and convert it to an object.
          #
          # Takes no arguments.
          #
          # Returns a Hash.
          Contract C::None => C::HashOf[String => C::Any]
          def rules
            @rules ||= begin
              ignored_keys = %w[description]

              relevant_entries = parsed_data.reject { |k, _| ignored_keys.include?(k) }
              relevant_entries.reject! { |k, _| k.start_with?("metadata_", "filter_", "modifier_") }

              # Review all entries
              affirmative = []
              mandatory = []
              negative = []
              relevant_entries.each do |k, v|
                function = function_for(k)
                unless whitelisted_methods.member?(function)
                  Entitlements.logger.fatal "The method #{k.inspect} is not allowed in #{filename}!"
                  raise "The method #{k.inspect} is not allowed in #{filename}!"
                end

                add_relevant_entries!(affirmative, function, v["="], filename)
                add_relevant_entries!(mandatory, function, v["&="], filename)
                add_relevant_entries!(negative, function, v["!="], filename)
              end

              # Expiration pre-processing: An entitlement that is expired as a whole should not
              # raise an error about having no conditions.
              if parsed_data.key?("modifier_expiration") && affirmative.empty?
                exp_date = parsed_data.fetch("modifier_expiration").fetch("=").first.fetch(:key)
                date = Entitlements::Util::Util.parse_date(exp_date)
                return {"always" => false} if date <= Time.now.utc.to_date
              end

              # There has to be at least one affirmative condition, not just all negative ones.
              # Override with `metadata_no_conditions_ok = true`.
              if affirmative.empty?
                return {"always" => false} if [true, "true"].include?(metadata["no_conditions_ok"])
                fatal_message("No conditions were found in #{filename}!")
              end

              # Get base affirmative and negative rules.
              result = affirmative_negative_rules(affirmative, negative)

              # Apply any mandatory rules.
              if mandatory.size == 1
                old_result = result.dup
                result = { "and" => [mandatory.first, old_result] }
              elsif mandatory.size > 1
                old_result = result.dup
                result = { "and" => [{ "or" => mandatory }, old_result] }
              end

              # Return what we've got.
              result
            end
          end

          # Handle affirmative and negative rules.
          #
          # affirmative - An array of Hashes with rules.
          # negative    - An array of Hashes with rules.
          #
          # Returns appropriate and / or hash.
          Contract C::ArrayOf[Hash], C::ArrayOf[Hash] => C::HashOf[String => C::Any]
          def affirmative_negative_rules(affirmative, negative)
            if negative.empty?
              # This is a simplified file. Just OR all the conditions together. (For
              # something more complicated, use YAML or ruby formats.)
              { "or" => affirmative }
            else
              # Each affirmative condition is OR'd, but any negative condition will veto.
              # For something more complicated, use YAML or ruby formats.
              {
                "and" => [
                  { "or" => affirmative },
                  { "and" => negative.map { |condition| { "not" => condition } } }
                ]
              }
            end
          end

          # Helper method to extract relevant entries from the parsed rules and concatenate them
          # onto the given array.
          #
          # array_to_update - An Array which will have relevant rules concat'd to it.
          # key             - String with the key.
          # rule_items      - An Array of Hashes with the rules to evaluate.
          # filename        - Filename where rule is defined (used for error printing).
          #
          # Updates and returns array_to_update.
          Contract C::ArrayOf[C::HashOf[String => String]], String, C::ArrayOf[C::HashOf[Symbol => String]], String => C::ArrayOf[C::HashOf[String => String]]
          def add_relevant_entries!(array_to_update, key, rule_items, filename)
            new_items = rule_items.reject { |item| expired?(item[:expiration], filename) }.map { |item| { key => item[:key] } }
            array_to_update.concat new_items
          end

          # Return the parsed data from the file. This is called on demand and cached.
          #
          # Takes no arguments.
          #
          # Returns a Hash.
          Contract C::None => C::HashOf[String => C::HashOf[String, C::ArrayOf[C::HashOf[Symbol, String]]]]
          def parsed_data
            @parsed_data ||= begin
              result = {}
              filter_keywords = Entitlements::Data::Groups::Calculated.filters_index.keys
              content = File.read(filename).split(/\n/)
              content.each do |raw_line|
                line = raw_line.strip

                # Ignore comments and blank lines
                next if line.start_with?("#") || line == ""

                # Ensure valid lines
                unless line =~ /\A([\w\-]+)\s*([&!]?=)\s*(.+?)\s*\z/
                  Entitlements.logger.fatal "Unparseable line #{line.inspect} in #{filename}!"
                  raise "Unparseable line #{line.inspect} in #{filename}!"
                end

                # Parsing
                raw_key, operator, val = Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3)

                key = if filter_keywords.include?(raw_key)
                  "filter_#{raw_key}"
                elsif MODIFIERS.include?(raw_key)
                  "modifier_#{raw_key}"
                else
                  raw_key
                end

                # Contractor function is used internally but may not be specified in the file by the user.
                if key == "contractor"
                  Entitlements.logger.fatal "The method #{key.inspect} is not permitted in #{filename}!"
                  raise "Rule Error: #{key} is not a valid function in #{filename}!"
                end

                result[key] ||= {}
                result[key]["="] ||= []
                result[key]["!="] ||= []
                result[key]["&="] ||= []

                # Semicolon predicates
                if key == "description"
                  result[key][operator] << { key: val }
                else
                  result[key][operator] << parsed_predicate(val)
                end
              end

              result
            end
          end

          # Parse predicate for a rule. Turn into a hash of { key: <String of Primary Value> + other keys in line }.
          #
          # val - The predicate string
          #
          # Returns a Hash.
          Contract String => C::HashOf[Symbol, String]
          def parsed_predicate(val)
            v = val.sub(/\s*#.*\z/, "")
            return { key: v } unless v.include?(";")

            parts = v.split(/\s*;\s*/)
            op_hash = { key: parts.shift }
            parts.each do |part|
              if part =~ /\A(\w+)\s*=\s*(\S+)\s*\z/
                predicate_keyword, predicate_value = Regexp.last_match(1), Regexp.last_match(2)
                unless SEMICOLON_PREDICATES.include?(predicate_keyword)
                  raise ArgumentError, "Rule Error: Invalid semicolon predicate #{predicate_keyword.inspect} in #{filename}!"
                end
                op_hash[predicate_keyword.to_sym] = predicate_value
              else
                raise ArgumentError, "Rule Error: Unparseable semicolon predicate #{part.inspect} in #{filename}!"
              end
            end
            op_hash
          end
        end
      end
    end
  end
end
