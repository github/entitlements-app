# frozen_string_literal: true

module Entitlements
  class Plugins
    class PosixGroup < Entitlements::Plugins
      include ::Contracts::Core
      C = ::Contracts

      # Produce the override hash for an LDAP posixGroup.
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
          "objectClass"  => "PosixGroup",
          "memberUid"    => members,
          "gidNumber"    => gid_number(group).to_s,
          "uniqueMember" => nil,
          "owner"        => nil
        }
      end

      # Get the gidNumber from the metadata in the group.
      #
      # group - Entitlements::Models::Group object
      #
      # Returns an Integer with the GID number of the group.
      Contract Entitlements::Models::Group => Integer
      def self.gid_number(group)
        unless group.metadata.key?("gid_number")
          raise ArgumentError, "POSIX Group #{group.dn} has no metadata setting for gid_number!"
        end

        result = group.metadata["gid_number"].to_i
        return result if result >= 1 && result < 65536
        raise ArgumentError, "POSIX Group #{group.dn} has GID #{result} out of 1-65535 range!"
      end
    end
  end
end
