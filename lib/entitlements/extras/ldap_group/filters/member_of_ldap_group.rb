# frozen_string_literal: true

# Filter class to remove members of a particular LDAP group.

module Entitlements
  module Extras
    class LDAPGroup
      class Filters
        class MemberOfLDAPGroup < Entitlements::Data::Groups::Calculated::Filters::Base
          include ::Contracts::Core
          C = ::Contracts

          # Determine if the member is filtered as per this definition. Return true if the member
          # is to be filtered out, false if the member does not match the filter.
          #
          # member - Entitlements::Models::Person object
          #
          # Returns true if the person is to be filtered out, false otherwise.
          Contract Entitlements::Models::Person => C::Bool
          def filtered?(member)
            return false if filter == :all
            return false unless member_of_ldap_group?(member, config.fetch("ldap_group"))
            return true if filter == :none
            !member_of_filter?(member)
          end

          # Helper method: Determine if the person is a member of an LDAP group that exists in
          # the directory but is not managed by entitlements.
          #
          # member   - Entitlements::Models::Person object
          # group_dn - LDAP distinguished name of the group
          #
          # Returns true if a member of the group, false otherwise.
          Contract Entitlements::Models::Person, String => C::Bool
          def member_of_ldap_group?(member, group_dn)
            Entitlements.cache[:member_of_ldap_group] ||= {}
            Entitlements.cache[:member_of_ldap_group][group_dn] ||= begin
              member_set = Entitlements::Extras::LDAPGroup::Rules::LDAPGroup.matches(value: group_dn)
              member_set.map { |person| person.uid.downcase }
            rescue Entitlements::Data::Groups::GroupNotFoundError
              []
            end

            Entitlements.cache[:member_of_ldap_group][group_dn].include?(member.uid.downcase)
          end
        end
      end
    end
  end
end
