# frozen_string_literal: true

require "set"

module Entitlements
  class Backend
    class BaseProvider
      include ::Contracts::Core
      C = ::Contracts

      # Dry run of committing changes. Returns a list of users added or removed.
      # Takes a group; looks up that same group in the appropriate backend.
      #
      # group         - An Entitlements::Models::Group object.
      # ignored_users - Optionally, a Set of lower-case Strings of users to ignore.
      #
      # Returns added / removed hash.
      Contract Entitlements::Models::Group, C::Maybe[C::SetOf[String]] => Hash[added: C::SetOf[String], removed: C::SetOf[String]]
      def diff(group, ignored_users = Set.new)
        existing_group = read(group.cn.downcase)
        return diff_existing_updated(existing_group, group, ignored_users)
      end

      # Dry run of committing changes. Returns a list of users added or removed.
      # Takes an existing and an updated group object, avoiding a lookup in the backend.
      #
      # existing_group - An Entitlements::Models::Group object.
      # group          - An Entitlements::Models::Group object.
      # ignored_users  - Optionally, a Set of lower-case Strings of users to ignore.
      Contract Entitlements::Models::Group, Entitlements::Models::Group, C::Maybe[C::SetOf[String]] => Hash[added: C::SetOf[String], removed: C::SetOf[String]]
      def diff_existing_updated(existing_group, group, ignored_users = Set.new)
        # The comparison needs to be done case-insensitive because some backends (e.g. GitHub organizations or teams)
        # may report members with different capitalization than is used in Entitlements. Keep track of correct capitalization
        # of member names here so they can be applied later. Note that `group` (from Entitlements) overrides `existing_group`
        # (from the backend).
        member_with_correct_capitalization = existing_group.member_strings.map { |ms| [ms.downcase, ms] }.to_h
        member_with_correct_capitalization.merge! group.member_strings.map { |ms| [ms.downcase, ms] }.to_h

        existing_members = existing_group.member_strings.map { |u| u.downcase }
        Entitlements::Util::Util.remove_uids(existing_members, ignored_users)

        proposed_members = group.member_strings.map { |u| u.downcase }
        Entitlements::Util::Util.remove_uids(proposed_members, ignored_users)

        added_members = proposed_members - existing_members
        removed_members = existing_members - proposed_members

        {
          added: Set.new(added_members.map { |ms| member_with_correct_capitalization[ms] }),
          removed: Set.new(removed_members.map { |ms| member_with_correct_capitalization[ms] })
        }
      end
    end
  end
end
