# frozen_string_literal: true

# Inherited methods for extras in this directory (or in other directories).

module Entitlements
  module Extras
    class Base
      include ::Contracts::Core
      C = ::Contracts

      # Retrieve the configuration for this extra from the Entitlements configuration
      # file. Returns the hash of configuration if found, or an empty hash in all other
      # cases.
      #
      # Takes no arguments.
      #
      # Returns a Hash.
      Contract C::None => C::HashOf[String => C::Any]
      def self.config
        @extra_config ||= begin
          # classname is something like "Entitlements::Extras::MyExtraClassName::Base" - want to pull
          # out the "MyExtraClassName" from this string.
          classname = self.to_s.split("::")[-2]
          decamelized_class = Entitlements::Util::Util.decamelize(classname)
          cfg = Entitlements.config.fetch("extras", {}).fetch(decamelized_class, nil)
          cfg.is_a?(Hash) ? cfg : {}
        end
      end

      # This is intended for unit tests to reset class variables.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      def self.reset!
        @extra_config = nil
      end
    end
  end
end
