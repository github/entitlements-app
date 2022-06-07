# frozen_string_literal: true

module Entitlements
  class Plugins
    class Dummy < Entitlements::Plugins
      include ::Contracts::Core
      C = ::Contracts

      # Dummy override hash.
      #
      # group         - Entitlements::Models::Group object
      # plugin_config - Additional configuration for the plugin
      # ldap          - Reference to the underlying Entitlements::Service::LDAP object
      #
      # Returns Hash with override settings.
      Contract Entitlements::Models::Group, C::HashOf[String => C::Any], Entitlements::Service::LDAP => C::HashOf[String => C::Any]
      def self.override_hash(_group, _plugin_config, _ldap)
        {}
      end
    end
  end
end
