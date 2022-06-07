# frozen_string_literal: true

module Entitlements
  class Backend
    class LDAP
      class Provider
        include ::Contracts::Core
        C = ::Contracts

        # Constructor.
        #
        # ldap       - Entitlements::Service::LDAP object
        Contract C::KeywordArgs[
          ldap: Entitlements::Service::LDAP,
        ] => C::Any
        def initialize(ldap:)
          @ldap = ldap
          @groups_in_ou_cache = {}

          # Keep track of each LDAP group we have read so we do not end up re-reading
          # certain referenced groups over and over again. This is at a program-wide level. If
          # multiple backends have the same namespace this will probably break.
          Entitlements.cache[:ldap_cache] ||= {}
        end

        # Read in a specific LDAP group and enumerate its members. Results are cached
        # for future runs.
        #
        # dn - A String with the DN of the group to read
        #
        # Returns a Entitlements::Models::Group object.
        Contract String => Entitlements::Models::Group
        def read(dn)
          Entitlements.cache[:ldap_cache][dn] ||= begin
            Entitlements.logger.debug "Loading group #{dn}"

            # Look up the group by its DN.
            result = ldap.search(base: dn, scope: Net::LDAP::SearchScope_BaseObject)

            # Ensure exactly one result found.
            unless result.size == 1 && result.key?(dn)
              raise Entitlements::Data::Groups::GroupNotFoundError, "No response from LDAP for dn=#{dn}"
            end

            Entitlements::Service::LDAP.entry_to_group(result[dn])
          end
        end

        # Read in LDAP groups within the specified OU and enumerate their members.
        # Results are cached for future runs so the read() method is faster.
        #
        # ou - A String with the base OU to search
        #
        # Returns a Set of Strings (DNs) of the groups in this OU.
        Contract String => C::SetOf[String]
        def read_all(ou)
          @groups_in_ou_cache[ou] ||= begin
            Entitlements.logger.debug "Loading all groups for #{ou}"

            # Find all groups in the OU
            raw = ldap.search(
              base: ou,
              filter: Net::LDAP::Filter.eq("cn", "*"),
              scope: Net::LDAP::SearchScope_SingleLevel
            )

            # Construct a Set of DNs from the result, and also cache the content of the
            # group to avoid a future lookup.
            result = Set.new
            raw.each do |dn, entry|
              Entitlements.cache[:ldap_cache][dn] = Entitlements::Service::LDAP.entry_to_group(entry)
              result.add dn
            end

            # Return that result
            result
          end
        end

        # Delete an LDAP group.
        #
        # dn - A String with the DN of the group to delete.
        #
        # Returns nothing.
        Contract String => nil
        def delete(dn)
          return if ldap.delete(dn)
          raise "Unable to delete LDAP group #{dn.inspect}!"
        end

        # Commit changes (upsert).
        #
        # group    - An Entitlements::Models::Group object.
        # override - An optional Hash of additional parameters that override defaults.
        #
        # Returns true if a change was made, false if no change was made.
        Contract Entitlements::Models::Group, C::Maybe[C::HashOf[String => C::Any]] => C::Bool
        def upsert(group, override = {})
          members = group.member_strings.map { |ms| ldap.person_dn_format.gsub("%KEY%", ms) }

          attributes = {
            "uniqueMember" => members,
            "description"  => group.description || "",
            "owner"        => [ldap.binddn],
            "objectClass"  => ["groupOfUniqueNames"],
            "cn"           => group.cn
          }.merge(override)
          override.each { |key, val| attributes.delete(key) if val.nil? }

          # LDAP schema does not allow empty groups but does allow a group to be a member of itself.
          # This gets around having to commit a dummy user in case an LDAP group is empty.
          if group.member_strings.empty?
            attributes["uniqueMember"] = [group.dn]
          end

          result = ldap.upsert(dn: group.dn, attributes: attributes)
          return result if result == true
          return false if result.nil?
          raise "Unable to upsert LDAP group #{group.dn.inspect}!"
        end

        private

        attr_reader :ldap
      end
    end
  end
end
