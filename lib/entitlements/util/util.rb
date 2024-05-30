# frozen_string_literal: true

module Entitlements
  class Util
    class Util
      include ::Contracts::Core
      C = ::Contracts

      # Downcase the first attribute of a distinguished name. This is used for case-insensitive
      # matching in `member_strings` and elsewhere.
      #
      # dn - A String with a distinguished name in the format xxx=<name_to_downcase>,yyy
      #
      # Returns a String with the distinguished name, downcased.
      Contract String => String
      def self.downcase_first_attribute(dn)
        return dn.downcase unless dn =~ /\A([^=]+)=([^,]+),(.+)\z/
        "#{Regexp.last_match(1)}=#{Regexp.last_match(2).downcase},#{Regexp.last_match(3)}"
      end

      # If something looks like a distinguished name, obtain and return the first attribute.
      # Otherwise return the input string.
      #
      # name_in - A String with either a name or a distinguished name
      #
      # Returns the name.
      Contract String => String
      def self.first_attr(name_in)
        name_in =~ /\A[^=]+=([^,]+),/ ? Regexp.last_match(1) : name_in
      end

      # Given a hash, validate options for correct data type and presence of required attributes.
      #
      # spec - A Hash with the specification (see contract)
      # data - A Hash with the actual options to test
      # text - A description of the thing being validated, to print in error messages
      #
      # Returns nothing but may raise error.
      Contract C::HashOf[String => { required: C::Bool, type: C::Or[Class, Array] }], C::HashOf[String => C::Any], String => nil
      def self.validate_attr!(spec, data, text)
        spec.each do |attr_name, config|
          # Raise if required attribute is not present.
          if config[:required] && !data.key?(attr_name)
            raise "#{text} is missing attribute #{attr_name}!"
          end

          # Skip the rest if the attribute isn't defined. (By the point the attribute is either
          # present or it's optional.)
          next unless data.key?(attr_name)

          # Make sure the attribute has the proper data type. Return when a match occurs.
          correct_type = [config[:type]].flatten.select { |type| data[attr_name].is_a?(type) }
          unless correct_type.any?
            existing = data[attr_name].class.to_s
            expected = [config[:type]].flatten.map { |clazz| clazz.to_s }.join(", ")
            raise "#{text} attribute #{attr_name.inspect} is supposed to be #{config[:type]}, not #{existing}!"
          end
        end

        extra_keys = data.keys - spec.keys
        if extra_keys.any?
          extra_keys_text = extra_keys.join(", ")
          raise "#{text} contains unknown attribute(s): #{extra_keys_text}"
        end

        nil
      end

      # From a group's key, get the directory where that group's files are defined. Normally this is
      # the entitlements path concatenated with the group's key, but it can be overridden with a "dir"
      # attribute on the group.
      #
      # group - A String with the key of the group as per the configuration file.
      #
      # Returns a String with the full directory path to the group.
      Contract String => String
      def self.path_for_group(group)
        unless Entitlements.config["groups"].key?(group)
          raise ArgumentError, "path_for_group: Group #{group.inspect} is not defined in the entitlements configuration!"
        end

        dir = Entitlements.config["groups"][group]["dir"]
        result_dir = if dir.nil?
                       File.join(Entitlements.config_path, group)
        elsif dir.start_with?("/")
          dir
        else
          File.expand_path(dir, Entitlements.config_path)
        end

        return result_dir if File.directory?(result_dir)
        raise Errno::ENOENT, "Non-existing directory #{result_dir.inspect} for group #{group.inspect}!"
      end

      # Get the common name from the distinguished name from either a String or an Entitlements::Models::Group.
      #
      # obj - Either a String (in DN format) or an Entitlements::Models::Group object.
      #
      # Returns a String with the common name.
      Contract C::Any => String
      def self.any_to_cn(obj)
        if obj.is_a?(Entitlements::Models::Group)
          return obj.cn.downcase
        end

        if obj.is_a?(String) && obj.start_with?("cn=")
          return Entitlements::Util::Util.first_attr(obj).downcase
        end

        if obj.is_a?(String)
          return obj
        end

        message = "Could not determine a common name from #{obj.inspect}!"
        raise ArgumentError, message
      end

      # Given an Array or a Set of uids or distinguished name, and a set of uids to be removed, delete any matching
      # uids from the original object in a case-insensitive matter. Compares simple strings, distinguished names, etc.
      #
      # obj  - A supported Enumerable or Entitlements::Models::Group (will be mutated)
      # uids - A Set of Strings with the uid(s) to be removed - uid(s) must all be lower case!
      #
      # Returns nothing but mutates `obj`.
      Contract C::Or[C::SetOf[String], C::ArrayOf[String]], C::Or[nil, C::SetOf[String]] => C::Any
      def self.remove_uids(obj, uids)
        return unless uids
        obj.delete_if do |uid|
          uids.member?(uid.downcase) || uids.member?(Entitlements::Util::Util.first_attr(uid).downcase)
        end
      end

      # Convert a string into CamelCase.
      #
      # str - The string that needs to be converted to CamelCase.
      #
      # Returns a String in CamelCase.
      Contract String => String
      def self.camelize(str)
        result = str.split(/[\W_]+/).collect! { |w| w.capitalize }.join

        # Special cases
        result.gsub("Github", "GitHub").gsub("Ldap", "LDAP")
      end

      # Convert CamelCase back into an identifier string.
      #
      # str - The CamelCase string to be converted to identifier_case.
      #
      # Returns a String.
      Contract String => String
      def self.decamelize(str)
        str.gsub("GitHub", "Github").gsub("LDAP", "Ldap").gsub(/([a-z\d])([A-Z])/, "\\1_\\2").downcase
      end

      # Returns a date object from the given input object.
      #
      # input - Any type of object that will be parsed as a date.
      #
      # Returns a date object.
      Contract C::Any => Date
      def self.parse_date(input)
        if input.is_a?(Date)
          return input
        end

        if input.is_a?(String)
          if input =~ /\A(\d{4})-?(\d{2})-?(\d{2})\z/
            return Date.new(Regexp.last_match(1).to_i, Regexp.last_match(2).to_i, Regexp.last_match(3).to_i)
          end

          raise ArgumentError, "Unsupported date format #{input.inspect} for parse_date!"
        end

        raise ArgumentError, "Unsupported object #{input.inspect} for parse_date!"
      end

      # Returns the absolute path to a file or directory. If the filename starts with "/" then that is the absolute
      # path. Otherwise the path returned is relative to the location of the Entitlements configuration file.
      #
      # path - String with the input path
      #
      # Returns a String with the full path.
      Contract String => String
      def self.absolute_path(path)
        return path if path.start_with?("/")
        entitlements_config_dirname = File.dirname(Entitlements.config_file)
        File.expand_path(path, entitlements_config_dirname)
      end

      def self.dns_for_ou(ou, cfg_obj)
        results = []
        path = path_for_group(ou)
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
            raise "Illegal LDAP group name #{file_without_extension.inspect} in #{ou}!"
          end
          group_dn = ["cn=#{file_without_extension}", cfg_obj.fetch("base")].join(",")

          results << group_dn
        end

        results
      end
    end
  end
end
