# frozen_string_literal: true

# This class provides common methods and is intended to be inherited by other audit providers.

module Entitlements
  class Auditor
    class Base
      include ::Contracts::Core
      C = ::Contracts

      attr_reader :description, :provider_id

      # ---------
      # Interface
      # ---------

      # Constructor.
      #
      # config - A Hash with configuration options
      Contract Logger, C::HashOf[String => C::Any] => C::Any
      def initialize(logger, config)
        @logger = logger
        @description = config["description"] || self.class.to_s
        @provider_id = config["provider_id"] || self.class.to_s.split("::").last
        @config = config
      end

      # Setup. This sets up the audit provider before any action takes place. This may be
      # declared in the child class.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => nil
      def setup
        # :nocov:
        nil
        # :nocov:
      end

      # Commit. This takes the entirety of group objects and actions and records them in
      # whatever methodology the audit provider uses.
      #
      # actions            - Array of Entitlements::Models::Action (all requested actions)
      # successful_actions - Array of Entitlements::Models::Action (successfully applied actions)
      # provider_exception - Exception raised by a provider when applying (hopefully nil)
      #
      # Returns nothing.
      Contract C::KeywordArgs[
        actions: C::ArrayOf[Entitlements::Models::Action],
        successful_actions: C::ArrayOf[Entitlements::Models::Action],
        provider_exception: C::Or[nil, Exception]
      ] => nil
      def commit(actions:, successful_actions:, provider_exception:)
        # :nocov:
        nil
        # :nocov:
      end

      # Set up a logger class that wraps incoming messages with the prefix and (if meaningful) the
      # provider ID. Messages are then sent with the requested priority to the actual logger object.
      class CustomLogger
        def initialize(underlying_object, underlying_logger)
          @underlying_object = underlying_object
          @underlying_logger = underlying_logger
        end

        def prefix
          @prefix ||= begin
            if @underlying_object.provider_id == @underlying_object.class.to_s.split("::").last
              @underlying_object.class.to_s
            else
              "#{@underlying_object.class}[#{@underlying_object.provider_id}]"
            end
          end
        end

        def method_missing(m, *args, &block)
          args[0] = "#{prefix}: #{args.first}"
          @underlying_logger.send(m, *args, &block)
        end
      end

      private

      attr_reader :config

      # Intercept calls to logger to wrap through the custom class.
      def logger
        @logger_class ||= CustomLogger.new(self, @logger)
      end

      # Raise a configuration error message.
      #
      # message - A String with the error message to be logged and raised.
      #
      # Returns nothing because it raises an error.
      Contract String => C::Any
      def configuration_error(message)
        provider = self.class.to_s.split("::").last
        error_message = "Configuration error for provider=#{provider} id=#{provider_id}: #{message}"
        logger.fatal "Configuration error: #{message}"
        raise ArgumentError, error_message
      end

      # Require the the configuration contain certain keys (no validation is performed on the
      # values - just make sure the key exists).
      #
      # required_keys - An Array of Strings with the required keys.
      #
      # Returns nothing.
      Contract C::ArrayOf[String] => nil
      def require_config_keys(required_keys)
        missing_keys = required_keys - config.keys
        return unless missing_keys.any?
        configuration_error "Not all required keys are defined. Missing: #{missing_keys.join(',')}."
      end

      # Convert a distinguished name (cn=something,ou=foo,dc=example,dc=net) to a file
      # path (dc=net/dc=example/ou=foo/cn=something).
      #
      # dn - A String with the distinguished name.
      #
      # Returns a String with the path.
      Contract String => String
      def path_from_dn(dn)
        File.join(dn.split(",").reverse)
      end

      # Convert a path (dc=net/dc=example/ou=foo/cn=something) to a distinguished name
      # (cn=something,ou=foo,dc=example,dc=net).
      #
      # path - A String with the path name.
      #
      # Returns a String with the distinguished name.
      Contract String => String
      def dn_from_path(path)
        path.split("/").reject { |i| i.empty? }.reverse.join(",")
      end

      # From a list of actions, return only the ones that have a net change in membership.
      # In other words, filter out the ones where only metadata / description / etc. has changed.
      #
      # actions - Incoming array of Entitlements::Models::Action
      #
      # Returns an array of Entitlements::Models::Action
      Contract C::ArrayOf[Entitlements::Models::Action] => C::ArrayOf[Entitlements::Models::Action]
      def actions_with_membership_change(actions)
        actions.select do |action|
          if action.updated.is_a?(Entitlements::Models::Person) || action.existing == :none
            # MemberOf or other modification to the person itself, not handled by this auditor
            false
          elsif action.updated.nil? || action.existing.nil?
            # Add/remove group always triggers a commit
            true
          else
            action.updated.member_strings_insensitive != action.existing.member_strings_insensitive
          end
        end
      end
    end
  end
end
