# frozen_string_literal: true

module Entitlements
  class Util
    class Override
      include ::Contracts::Core
      C = ::Contracts

      # Handle override from plugin. Return hash, compatible with `upsert` method, that
      # defines the necessary differences.
      #
      # plugin - A Hash with the plugin configuration, both filename and target class (can be nil)
      # group  - The Entitlements::Models::Group
      # ldap   - Reference to the underlying Entitlements::Service::LDAP object
      #
      # Returns a Hash or nil.
      Contract C::Or[C::HashOf[String => String], nil], Entitlements::Models::Group, Entitlements::Service::LDAP => C::Or[nil, C::HashOf[String => C::Any]]
      def self.override_hash_from_plugin(plugin, group, ldap)
        return unless plugin

        # Plugin hash should consist of a Hash with 2 keys: "file" the absolute path to the file or relative path compared to
        # the entitlements configuration file, and "class" the class name that's contained within the file. If the filename
        # has no "/" then it is treated as a built-in plugin, under the "plugins" directory within this gem.
        unless plugin.key?("file")
          raise ArgumentError, "plugin configuration hash must contain 'file' key"
        end

        file = if plugin["file"] !~ %r{/}
          File.expand_path(File.join("../plugins", plugin["file"]), File.dirname(__FILE__))
        elsif plugin["file"].start_with?("/")
          plugin["file"]
        else
          File.expand_path(plugin["file"], File.dirname(Entitlements.config_file))
        end

        unless File.file?(file)
          raise ArgumentError, "Could not locate plugin for #{plugin['file'].inspect} at #{file.inspect}"
        end

        unless plugin.key?("class")
          raise ArgumentError, "plugin configuration hash must contain 'class' key"
        end

        require file

        clazz = Kernel.const_get("Entitlements::Plugins::#{plugin['class']}")

        unless clazz.respond_to?(:loaded?) && clazz.loaded?
          raise ArgumentError, "Plugin Entitlements::Plugins::#{plugin['class']} should inherit Entitlements::Plugins"
        end

        unless clazz.respond_to?(:override_hash)
          raise ArgumentError, "Plugin Entitlements::Plugins::#{plugin['class']} must implement override_hash method"
        end

        override_hash = clazz.override_hash(group, plugin, ldap)
        return override_hash if override_hash.is_a?(Hash)

        type = override_hash.class
        raise ArgumentError, "Plugin Entitlements::Plugins::#{plugin['class']}.override_hash must return hash, not #{type}"
      end
    end
  end
end
