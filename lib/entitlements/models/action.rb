# frozen_string_literal: true

module Entitlements
  class Models
    class Action
      include ::Contracts::Core
      C = ::Contracts

      # Constructor.
      #
      # dn       - Distinguished name of action.
      # existing - Current data according to data source.
      # updated  - Current data according to entitlements.
      # ou       - String with the OU as per entitlements.
      # ignored_users - Optionally, a set of strings with users to ignore
      Contract String, C::Or[nil, Entitlements::Models::Group, :none], C::Or[nil, Entitlements::Models::Group, Entitlements::Models::Person], String, C::KeywordArgs[ignored_users: C::Maybe[C::SetOf[String]]] => C::Any
      def initialize(dn, existing, updated, ou, ignored_users: Set.new)
        @dn = dn
        @existing = existing
        @updated = updated
        @ou = ou
        @implementation = nil
        @ignored_users = ignored_users
      end

      # Element readers.
      attr_reader :dn, :existing, :updated, :ou, :implementation, :ignored_users

      # Determine if the change type is add, delete, or update.
      Contract C::None => Symbol
      def change_type
        return :add if existing.nil?
        return :delete if updated.nil?
        :update
      end

      # Get the configuration for the OU holding the group.
      #
      # Takes no arguments.
      #
      # Returns a configuration hash.
      Contract C::None => C::HashOf[String => C::Any]
      def config
        Entitlements.config["groups"].fetch(ou)
      end

      # Determine the type of the OU (defaults to ldap if undefined).
      #
      # Takes no arguments.
      #
      # Returns a string with the configuration type.
      Contract C::None => String
      def ou_type
        config["type"] || "ldap"
      end

      # Determine the short name of the DN.
      #
      # Takes no arguments.
      #
      # Returns a string with the short name of the DN.
      Contract C::None => String
      def short_name
        dn =~ /\A(\w+)=(.+?),/ ? Regexp.last_match(2) : dn
      end

      # Add an implementation. This is for providers and services that do not have a 1:1 mapping
      # between entitlements groups and implementing changes on the back end.
      #
      # data - Hash of Symbols with information that is meaningful to the back end.
      #
      # Returns nothing.
      # :nocov:
      Contract C::HashOf[Symbol => C::Any] => C::Any
      def add_implementation(data)
        @implementation ||= []
        @implementation << data
      end
      # :nocov:
    end
  end
end
