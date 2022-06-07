# frozen_string_literal: true
# Is someone in an LDAP group?

module Entitlements
  class Data
    class Groups
      class Calculated
        class Rules
          class Group < Entitlements::Data::Groups::Calculated::Rules::Base

            FILE_EXTENSIONS = {
              "rb"   => "Entitlements::Data::Groups::Calculated::Ruby",
              "txt"  => "Entitlements::Data::Groups::Calculated::Text",
              "yaml" => "Entitlements::Data::Groups::Calculated::YAML"
            }

            # Interface method: Get a Set[Entitlements::Models::Person] matching this condition.
            #
            # value    - The value to match.
            # filename - Name of the file resulting in this rule being called
            # options  - Optional hash of additional method-specific options
            #
            # Returns a Set[Entitlements::Models::Person].
            Contract C::KeywordArgs[
              value: String,
              filename: C::Maybe[String],
              options: C::Optional[C::HashOf[Symbol => C::Any]]
            ] => C::SetOf[Entitlements::Models::Person]
            def self.matches(value:, filename: nil, options: {})
              # We've asked for a managed group, so we need to calculate that group and return its members.
              # First parse the value into the ou and cn.
              raise "Error: Unexpected value #{value.inspect} in #{self.class}!" unless value =~ %r{\A(.+)/([^/]+)\z}
              ou = value.rpartition("/").first
              cn = value.rpartition("/").last

              # Check the cache. If we are in the process of calculating it, it's a circular dependency that should be alerted upon.
              # If we've already calculated this, just return the value.
              current_value = Entitlements.cache[:calculated].fetch(ou, {}).fetch(cn, nil)
              if current_value == :calculating
                Entitlements.cache[:dependencies] << "#{ou}/#{cn}"
                raise "Error: Circular dependency #{Entitlements.cache[:dependencies].join(' -> ')}"
              end

              # If we have calculated this before, then apply modifiers and return the result. `current_value` here
              # is a set with the correct answers but that does not take into effect any modifiers. Therefore we
              # reference back to the object so we can have the modifiers applied. There's a cache in the object that
              # remembers the value of `.modified_members` each time it's calculated, so this is inexpensive.
              filebase_with_path = File.join(Entitlements::Util::Util.path_for_group(ou), cn)
              if Entitlements.cache[:file_objects].key?(filebase_with_path)
                return Entitlements.cache[:file_objects][filebase_with_path].modified_members
              end

              # We actually need to calculate this group. Find the file based on the ou and cn in the directory.
              files = files_for(ou, options: options)
              match_regex = Regexp.new("\\A" + Regexp.escape(cn.gsub("*", "\f")).gsub("\\f", ".*") + "\\z")
              matching_files = files.select { |base, _ext| match_regex.match(base) }
              if matching_files.any?
                result = Set.new
                matching_files.each do |filebase, ext|
                  filebase_with_path = File.join(Entitlements::Util::Util.path_for_group(ou), filebase)

                  # If the object has already been calculated then we can just merge the value from
                  # the cache without going any further. Otherwise, create a new object for the group
                  # reference and calculate them.
                  unless Entitlements.cache[:file_objects][filebase_with_path]
                    clazz = Kernel.const_get(FILE_EXTENSIONS[ext])
                    Entitlements.cache[:file_objects][filebase_with_path] = clazz.new(
                      filename: "#{filebase_with_path}.#{ext}",
                    )
                    if Entitlements.cache[:file_objects][filebase_with_path].members == :calculating
                      next if matching_files.size > 1
                      raise "Error: Invalid self-referencing wildcard in #{ou}/#{filebase}.#{ext}"
                    end
                  end

                  unless Entitlements.cache[:file_objects][filebase_with_path].modified_members == :calculating
                    result.merge Entitlements.cache[:file_objects][filebase_with_path].modified_members
                  end
                end
                return result
              end

              # No file exists... handle accordingly
              path = File.join(Entitlements::Util::Util.path_for_group(ou), "#{cn}.(rb|txt|yaml)")
              if options[:skip_broken_references]
                Entitlements.logger.warn "Could not find a configuration for #{path} - skipped (filename: #{filename.inspect})"
                return Set.new
              end

              Entitlements.logger.fatal "Error: Could not find a configuration for #{path} (filename: #{filename.inspect})"
              raise "Error: Could not find a configuration for #{path} (filename: #{filename.inspect})"
            end

            # Enumerate and cache all files in a directory for more efficient processing later.
            #
            # path - A String with the directory structure relative to Entitlements.config_path
            #
            # Returns a Set of Hashes with { "file_without_extension" => "extension" }
            Contract String, C::KeywordArgs[options: C::HashOf[Symbol => C::Any]] => C::HashOf[String => String]
            def self.files_for(path, options:)
              @files_for_cache ||= {}
              @files_for_cache[path] ||= begin
                full_path = Entitlements::Util::Util.path_for_group(path)
                if File.directory?(full_path)
                  result = {}
                  Dir.entries(full_path).each do |name|
                    next if name.start_with?(".")
                    next unless name.end_with?(*FILE_EXTENSIONS.keys.map { |k| ".#{k}" })
                    next unless File.file?(File.join(full_path, name))
                    raise "Unparseable name: #{full_path}/#{name}" unless name =~ /\A(.+)\.(\w+)\z/
                    result[Regexp.last_match(1)] = Regexp.last_match(2)
                  end
                  result
                elsif options[:skip_broken_references]
                  Entitlements.logger.warn "Could not find any configuration in #{full_path} - skipped"
                  {}
                else
                  message = "Error: Could not find any configuration in #{full_path}"
                  Entitlements.logger.fatal message
                  raise RuntimeError, message
                end
              end
            end
          end
        end
      end
    end
  end
end
