# frozen_string_literal: true

module Entitlements
  class Plugins
    class GroupOfNames < Entitlements::Plugins
      include ::Contracts::Core
      C = ::Contracts

      # Produce the override hash for an LDAP groupOfNames.
      #
      # group         - Entitlements::Models::Group object
      # plugin_config - Additional configuration for the plugin
      # ldap          - Reference to the underlying Entitlements::Service::LDAP object
      #
      # Returns Hash with override settings.
      Contract Entitlements::Models::Group, C::HashOf[String => C::Any], Entitlements::Service::LDAP => C::HashOf[String => C::Any]
      def self.override_hash(group, _plugin_config, ldap)
        members = group.member_strings.map { |ms| ldap.person_dn_format.gsub("%KEY%", ms) }

        {
          "objectClass"  => "GroupOfNames",
          "member"       => members,
          "uniqueMember" => nil
        }
      end
    end
  end
end
