# frozen_string_literal: true

# To add a new backend, make its "Controller" class inherit from Entitlements::Backend::BaseController.
# Consider using dummy/controller.rb as a template for a brand new class.

# Needed to register backends
require_relative "../cli"
require_relative "../util/util"

module Entitlements
  class Backend
    class BaseController
      include ::Contracts::Core
      C = ::Contracts

      # Upon loading of the class itself, register the class in the list of available
      # backends that is tracked in the Entitlements class.
      def self.register
        Entitlements.register_backend(identifier, self, priority)
      end

      # Default priority is 10 - override by defining this method in the child class.
      def self.priority
        10
      end

      # :nocov:
      def priority
        self.class.priority
      end
      # :nocov:

      # Default identifier is the de-camelized name of the class - override by defining this method in the child class.
      def self.identifier
        classname = self.to_s.split("::")[-2]
        Entitlements::Util::Util.decamelize(classname)
      end

      COMMON_GROUP_CONFIG = {
        "allowed_methods" => { required: false, type: Array },
        "allowed_types"   => { required: false, type: Array },
        "dir"             => { required: false, type: String }
      }

      # Constructor. Generic constructor that takes a hash of configuration options.
      #
      # group_name - Name of the corresponding group in the entitlements configuration file.
      # config     - Optionally, a Hash of configuration information (configuration is referenced if empty).
      Contract String, C::Maybe[C::HashOf[String => C::Any]] => C::Any
      def initialize(group_name, config = nil)
        @group_name = group_name
        @config = config ? config.dup : Entitlements.config["groups"].fetch(group_name).dup
        @config.delete("type")
        @actions = []
        @logger = Entitlements.logger
        validate_config!(@group_name, @config)
      end

      attr_reader :actions

      # Print difference array.
      #
      # key           - String with the key identifying the OU
      # added         - Array[Entitlements::Models::Action]
      # removed       - Array[Entitlements::Models::Action]
      # changed       - Array[Entitlements::Models::Action]
      # ignored_users - Optionally a Set of Strings with usernames to ignore
      #
      # Returns nothing (this just prints to logger).
      Contract C::KeywordArgs[
        key: String,
        added:   C::ArrayOf[Entitlements::Models::Action],
        removed: C::ArrayOf[Entitlements::Models::Action],
        changed: C::ArrayOf[Entitlements::Models::Action],
        ignored_users: C::Maybe[C::SetOf[String]]
      ] => C::Any
      def print_differences(key:, added:, removed:, changed:, ignored_users: Set.new)
        added_array   = added.map   { |i| [i.dn, :added,   i] }
        removed_array = removed.map { |i| [i.dn, :removed, i] }
        changed_array = changed.map { |i| [i.dn, :changed, i] }

        combined = (added_array + removed_array + changed_array).sort_by { |i| i.first.to_s.downcase }
        combined.each do |entry|
          identifier = entry[0]
          changetype = entry[1]
          obj        = entry[2]

          if changetype == :added
            members = obj.updated.member_strings.map { |i| i =~ /\Auid=(.+?),/ ? Regexp.last_match(1) : i }
            Entitlements.logger.info "ADD #{identifier} to #{key} (Members: #{members.sort.join(',')})"
          elsif changetype == :removed
            Entitlements.logger.info "DELETE #{identifier} from #{key}"
          else
            ignored_users.merge obj.ignored_users
            existing_members = obj.existing.member_strings
            Entitlements::Util::Util.remove_uids(existing_members, ignored_users)

            proposed_members = obj.updated.member_strings
            Entitlements::Util::Util.remove_uids(proposed_members, ignored_users)

            added_to_group = (proposed_members - existing_members).map { |i| [i, "+"] }
            removed_from_group = (existing_members - proposed_members).map { |i| [i, "-"] }

            # Filter out case-only differences. For example if "bob" is in existing and "BOB" is in proposed,
            # we don't want to show this as a difference.
            downcase_proposed_members = proposed_members.map { |m| m.downcase }
            downcase_existing_members = existing_members.map { |m| m.downcase }
            duplicated = downcase_proposed_members & downcase_existing_members
            added_to_group.reject! { |m| duplicated.include?(m.first.downcase) }
            removed_from_group.reject! { |m| duplicated.include?(m.first.downcase) }

            # What's left is actual changes.
            combined_group = (added_to_group + removed_from_group).sort_by { |i| i.first.downcase }
            if combined_group.any?
              Entitlements.logger.info "CHANGE #{identifier} in #{key}"
              combined_group.each do |item, item_changetype|
                Entitlements.logger.info ".  #{item_changetype} #{item}"
              end
            end

            if obj.existing.description != obj.updated.description && obj.ou_type == "ldap"
              Entitlements.logger.info "METADATA CHANGE #{identifier} in #{key}"
              Entitlements.logger.info "- Old description: #{obj.existing.description.inspect}"
              Entitlements.logger.info "+ New description: #{obj.updated.description.inspect}"
            end
          end
        end
      end

      # Get count of changes.
      #
      # Takes no arguments.
      #
      # Returns an Integer.
      Contract C::None => Integer
      def change_count
        actions.size
      end

      # Stub methods
      # :nocov:
      def prefetch
        # Can be left undefined
      end

      def validate
        # Can be left undefined
      end

      def calculate
        raise "Must be defined in child class"
      end

      def preapply
        # Can be left undefined
      end

      def apply(action)
        raise "Must be defined in child class"
      end

      def validate_config!(key, data)
        # Can be left undefined (but really shouldn't)
      end

      private

      attr_reader :config, :group_name, :logger
    end
  end
end
