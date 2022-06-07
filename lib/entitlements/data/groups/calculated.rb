# frozen_string_literal: true

require_relative "calculated/base"
require_relative "calculated/ruby"
require_relative "calculated/text"
require_relative "calculated/yaml"

# Calculate groups that should exist and the contents of each based on a set of rules
# defined within a directory. The calculation of members is global across the entire
# entitlements system, so this is a singleton class.

module Entitlements
  class Data
    class Groups
      class Calculated
        include ::Contracts::Core
        C = ::Contracts

        FILE_EXTENSIONS = {
          "rb"   => "Entitlements::Data::Groups::Calculated::Ruby",
          "txt"  => "Entitlements::Data::Groups::Calculated::Text",
          "yaml" => "Entitlements::Data::Groups::Calculated::YAML"
        }

        @groups_in_ou_cache = {}
        @groups_cache = {}
        @config_cache = {}

        # Reset all module state
        #
        # Takes no arguments
        def self.reset!
          @rules_index = {
            "group"    => Entitlements::Data::Groups::Calculated::Rules::Group,
            "username" => Entitlements::Data::Groups::Calculated::Rules::Username
          }

          @filters_index = {}
          @groups_in_ou_cache = {}
          @groups_cache = {}
          @config_cache = {}
        end

        # Construct a group object.
        #
        # Takes no arguments.
        #
        # Returns a Entitlements::Models::Group object.
        Contract String => Entitlements::Models::Group
        def self.read(dn)
          return @groups_cache[dn] if @groups_cache[dn]
          raise "read(#{dn.inspect}) does not support calculation at this time. Please use read_all() first to build cache."
        end

        # Calculate all groups within the specified OU and enumerate their members.
        # Results are cached for future runs so the read() method is faster.
        #
        # ou_key  - String with the key from the configuration file.
        # cfg_obj - Hash with the configuration for that key from the configuration file.
        #
        # Returns a Set of Strings (DNs) of the groups in this OU.
        Contract String, C::HashOf[String => C::Any], C::KeywordArgs[
          skip_broken_references: C::Optional[C::Bool]
        ] => C::SetOf[String]
        def self.read_all(ou_key, cfg_obj, skip_broken_references: false)
          return read_mirror(ou_key, cfg_obj) if cfg_obj["mirror"]

          @config_cache[ou_key] ||= cfg_obj
          @groups_in_ou_cache[ou_key] ||= begin
            Entitlements.logger.debug "Calculating all groups for #{ou_key}"
            Entitlements.logger.debug "!!! skip_broken_references is enabled" if skip_broken_references

            result = Set.new
            Entitlements.cache[:file_objects] ||= {}

            # Iterate over all the files in the configuration directory for this OU
            path = Entitlements::Util::Util.path_for_group(ou_key)
            Dir.glob(File.join(path, "*")).each do |filename|
              # If it's a directory, skip it for now.
              if File.directory?(filename)
                next
              end

              # If the file is ignored (e.g. documentation) then skip it.
              if Entitlements::IGNORED_FILES.member?(File.basename(filename))
                next
              end

              # Determine the group DN. The CN will be the filname without its extension.
              file_without_extension = File.basename(filename).sub(/\.\w+\z/, "")
              unless file_without_extension =~ /\A[\w\-]+\z/
                raise "Illegal LDAP group name #{file_without_extension.inspect} in #{ou_key}!"
              end
              group_dn = ["cn=#{file_without_extension}", cfg_obj.fetch("base")].join(",")

              # Use the ruleset to build the group.
              options = { skip_broken_references: skip_broken_references }

              Entitlements.cache[:file_objects][filename] ||= ruleset(filename: filename, config: cfg_obj, options: options)
              @groups_cache[group_dn] = Entitlements::Models::Group.new(
                dn: group_dn,
                members: Entitlements.cache[:file_objects][filename].modified_filtered_members,
                description: Entitlements.cache[:file_objects][filename].description,
                metadata: Entitlements.cache[:file_objects][filename].metadata.merge("_filename" => filename)
              )
              result.add group_dn
            end

            result
          end
        end

        # Return the group cache as a hash.
        #
        # Takes no arguments.
        #
        # Returns a hash { dn => Entitlements::Models::Group }
        # :nocov:
        Contract C::None => C::HashOf[String => Entitlements::Models::Group]
        def self.to_h
          @groups_cache
        end
        # :nocov:

        # Get the entire output organized by OU.
        #
        # Takes no arguments.
        #
        # Returns a Hash of OU to the configuration and group objects it contains.
        Contract C::None => C::HashOf[String => { config: C::HashOf[String => C::Any], groups: C::HashOf[String => Entitlements::Models::Group]}]
        def self.all_groups
          @groups_in_ou_cache.map do |ou_key, dn_in_ou|
            if @config_cache.key?(ou_key)
              [
                ou_key,
                {
                  config: @config_cache[ou_key],
                  groups: dn_in_ou.sort.map { |dn| [dn, @groups_cache.fetch(dn)] }.to_h
                }
              ]
            else
              nil
            end
          end.compact.to_h
        end

        # Calculate the groups within the specified mirrored OU. This requires that
        # read_all() has run already on the mirrored OU. This will not re-calculate
        # the results, but rather just duplicate the results and adjust the OUs.
        #
        # ou_key  - String with the key from the configuration file.
        # cfg_obj - Hash with the configuration for that key from the configuration file.
        #
        # Returns a Set of Strings (DNs) of the groups in this OU.
        Contract String, C::HashOf[String => C::Any] => C::SetOf[String]
        def self.read_mirror(ou_key, cfg_obj)
          @groups_in_ou_cache[ou_key] ||= begin
            Entitlements.logger.debug "Mirroring #{ou_key} from #{cfg_obj['mirror']}"

            unless @groups_in_ou_cache[cfg_obj["mirror"]]
              raise "Cannot read_mirror on #{ou_key.inspect} because read_all has not occurred on #{cfg_obj['mirror'].inspect}!"
            end

            result = Set.new
            @groups_in_ou_cache[cfg_obj["mirror"]].each do |source_dn|
              source_group = @groups_cache[source_dn]
              unless source_group
                raise "No group has been calculated for #{source_dn.inspect}!"
              end

              new_dn = ["cn=#{source_group.cn}", cfg_obj["base"]].join(",")
              @groups_cache[new_dn] ||= source_group.copy_of(new_dn)
              result.add new_dn
            end

            result
          end
        end

        # Construct the ruleset object for a given filename.
        #
        # filename - A String with the filename.
        #
        # Returns an Entitlements::Data::Groups::Calculated::* object.
        Contract C::KeywordArgs[
          filename: String,
          config: C::HashOf[String => C::Any],
          options: C::Optional[C::HashOf[Symbol => C::Any]]
        ] => C::Or[
          Entitlements::Data::Groups::Calculated::Ruby,
          Entitlements::Data::Groups::Calculated::Text,
          Entitlements::Data::Groups::Calculated::YAML,
        ]
        def self.ruleset(filename:, config:, options: {})
          unless filename =~ /\.(\w+)\z/
            raise ArgumentError, "Unable to determine the extension on #{filename.inspect}!"
          end
          ext = Regexp.last_match(1)

          unless FILE_EXTENSIONS[ext]
            Entitlements.logger.fatal "Unable to map filename #{filename.inspect} to a ruleset object!"
            raise ArgumentError, "Unable to map filename #{filename.inspect} to a ruleset object!"
          end

          if config.key?("allowed_types")
            unless config["allowed_types"].is_a?(Array)
              Entitlements.logger.fatal "Configuration error: allowed_types should be an Array, got #{config['allowed_types'].inspect}"
              raise ArgumentError, "Configuration error: allowed_types should be an Array, got #{config['allowed_types'].class}!"
            end

            unless config["allowed_types"].include?(ext)
              allowed_join = config["allowed_types"].join(",")
              Entitlements.logger.fatal "Files with extension #{ext.inspect} are not allowed in this OU! Allowed: #{allowed_join}!"
              raise ArgumentError, "Files with extension #{ext.inspect} are not allowed in this OU! Allowed: #{allowed_join}!"
            end
          end

          clazz = Kernel.const_get(FILE_EXTENSIONS[ext])
          clazz.new(filename: filename, config: config, options: options)
        end

        #########################
        # This section is handled as a class variable not an instance variable because rule definitions
        # are global throughout the program.
        #########################

        @rules_index = {
          "group"    => Entitlements::Data::Groups::Calculated::Rules::Group,
          "username" => Entitlements::Data::Groups::Calculated::Rules::Username
        }

        @filters_index = {}

        # Retrieve the current rules index from the class.
        #
        # Takes no arguments.
        #
        # Returns a Hash.
        Contract C::None => C::HashOf[String => Class]
        def self.rules_index
          @rules_index
        end

        # Retrieve the current filters index from the class.
        #
        # Takes no arguments.
        #
        # Returns a Hash.
        Contract C::None => C::HashOf[String => Object]
        def self.filters_index
          @filters_index
        end

        # Retrieve the filters in the format used as default / starting point in other parts
        # of the program: { "filter_name_1" => :none, "filter_name_2" => :none }
        #
        # Takes no arguments.
        #
        # Returns a Hash in the indicated format.
        def self.filters_default
          @filters_index.map { |k, _| [k, :none] }.to_h
        end

        # Register a rule (requires namespace and class references). Methods are registered
        # per rule, not per instantiation.
        #
        # rule_name - String with the rule name.
        # clazz     - Class that implements the rule.
        #
        # Returns the class that implements the rule.
        Contract String, Class => Class
        def self.register_rule(rule_name, clazz)
          @rules_index[rule_name] = clazz
        end

        # Register a filter (requires namespace and object references). Named filters are instantiated
        # objects. It's possible to have multiple instantiations of the same class of filter.
        #
        # filter_name - String with the filter name.
        # filter_cfg  - Hash with a configuration for the filter.
        #
        # Returns the configuration of the filter object (a hash).
        Contract String, C::HashOf[Symbol => Object] => C::HashOf[Symbol => Object]
        def self.register_filter(filter_name, filter_cfg)
          @filters_index[filter_name] = filter_cfg
        end
      end
    end
  end
end
