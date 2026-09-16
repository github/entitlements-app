# frozen_string_literal: true

# Auditor that converts the graph computed by Entitlements into a queryable SQLite database.
#
# Configuration:
#
#   auditors:
#     - auditor_class: SQLite
#       path: /var/lib/entitlements/entitlements.db
#       person_attributes:
#         - shellentitlements
#
# `path` is required. `person_attributes` is an optional allowlist of person attributes to
# include; when it is not given, only user IDs are recorded, which keeps the artifact free
# of additional personal data.

module Entitlements
  class Auditor
    class SQLite < Entitlements::Auditor::Base
      include ::Contracts::Core
      C = ::Contracts

      # Setup. Validate the configuration and make sure the optional sqlite3 dependency is
      # actually installed before any changes are applied.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => nil
      def setup
        require_config_keys(%w[path])

        unless config["path"].is_a?(String)
          configuration_error "The 'path' must be a String, got #{config['path'].class}"
        end

        unless person_attributes.all? { |attribute| attribute.is_a?(String) }
          configuration_error "The 'person_attributes' must be an Array of Strings"
        end

        begin
          Entitlements::Graph::SQLiteWriter.load_driver!
        rescue Entitlements::Graph::SQLiteWriter::DriverUnavailable => e
          configuration_error e.message
        end

        nil
      end

      # Commit. Build a snapshot of the calculated graph and write it out.
      #
      # actions            - Array of Entitlements::Models::Action (all requested actions)
      # successful_actions - Set of Strings with the DNs of successfully applied actions
      # provider_exception - Exception raised by a provider when applying (hopefully nil)
      #
      # Returns nothing.
      Contract C::KeywordArgs[
        actions: C::ArrayOf[Entitlements::Models::Action],
        successful_actions: C::Or[C::SetOf[String], C::ArrayOf[String]],
        provider_exception: C::Or[nil, Exception]
      ] => nil
      def commit(actions:, successful_actions:, provider_exception:)
        snapshot = Entitlements::Graph::Snapshot.new(
          actions: actions,
          successful_actions: successful_actions,
          person_attributes: person_attributes,
          provider_exception: provider_exception
        )

        path = Entitlements::Graph::SQLiteWriter.new(snapshot).write!(config["path"])

        logger.debug "Wrote #{snapshot.groups.size} group(s) and #{snapshot.memberships.size} membership(s) to #{path}"
        nil
      end

      private

      # The allowlist of person attributes to record in the database. The type is validated
      # here rather than in `setup`, which calls this method as part of its validation.
      #
      # Takes no arguments.
      #
      # Returns an Array.
      Contract C::None => C::ArrayOf[C::Any]
      def person_attributes
        value = config["person_attributes"]
        return [] if value.nil?
        return value if value.is_a?(Array)
        configuration_error "The 'person_attributes' must be an Array, got #{value.class}"
      end
    end
  end
end
