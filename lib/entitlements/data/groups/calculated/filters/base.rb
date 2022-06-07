# frozen_string_literal: true

# Filter class to remove members of a particular LDAP group.

require "yaml"

module Entitlements
  class Data
    class Groups
      class Calculated
        class Filters
          class Base
            include ::Contracts::Core
            C = ::Contracts

            # Interface method: Determine if the member is filtered as per this definition.
            #
            # member - Entitlements::Models::Person object
            #
            # Return true if the member is to be filtered out, false if the member does not match the filter.
            Contract Entitlements::Models::Person => C::Bool
            def filtered?(_member)
              # :nocov:
              raise "Must be implemented in child class"
              # :nocov:
            end

            # Constructor.
            #
            # filter - Either :none, :all, or an array of string conditions passed through to the filter
            # config - Configuration data (Hash, optional)
            Contract C::KeywordArgs[
              filter: C::Or[:none, C::ArrayOf[String]],
              config: C::Maybe[Hash]
            ] => C::Any
            def initialize(filter:, config: {})
              @filter = filter
              @config = config
            end

            private

            attr_reader :config, :filter

            # Helper method: Determine if the person is listed in an array of filter conditions.
            # Filter conditions that have no `/` are interpreted to be usernames, whereas filter
            # conditions with a `/` refer to LDAP entitlement groups.
            #
            # member - Entitlements::Models::Person object
            #
            # Returns true if a member of the filter conditions, false otherwise.
            Contract Entitlements::Models::Person => C::Bool
            def member_of_filter?(member)
              # First handle all username entries, regardless of order, because we do not
              # have to mess around with reading groups for those.
              filter.reject { |filter_val| filter_val =~ /\// }.each do |filter_val|
                return true if filter_val.downcase == member.uid.downcase
              end

              # Now handle all group entries.
              filter.select { |filter_val| filter_val =~ /\// }.each do |filter_val|
                return true if member_of_named_group?(member, filter_val)
              end

              # If we get here there was no match.
              false
            end

            # Helper method: Determine if the person is a member of a specific LDAP group named
            # in entitlements style.
            #
            # member    - Entitlements::Models::Person object
            # group_ref - Optionally a string with a reference to a group to look up
            #
            # Returns true if a member of the group, false otherwise.
            Contract Entitlements::Models::Person, String => C::Bool
            def member_of_named_group?(member, group_ref)
              Entitlements.cache[:member_of_named_group] ||= {}
              Entitlements.cache[:member_of_named_group][group_ref] ||= begin
                member_set = Entitlements::Data::Groups::Calculated::Rules::Group.matches(
                  value: group_ref,
                )
                member_set.map { |person| person.uid.downcase }
              end

              Entitlements.cache[:member_of_named_group][group_ref].include?(member.uid.downcase)
            end
          end
        end
      end
    end
  end
end
