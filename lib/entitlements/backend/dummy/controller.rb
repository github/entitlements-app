# frozen_string_literal: true

module Entitlements
  class Backend
    class Dummy
      class Controller < Entitlements::Backend::BaseController
        register

        # :nocov:
        include ::Contracts::Core
        C = ::Contracts

        # Pre-fetch the existing group membership in each OU.
        #
        # Takes no arguments.
        #
        # Returns nothing. (Populates cache.)
        Contract C::None => C::Any
        def prefetch
          # This does nothing.
        end

        # Validation routines.
        #
        # Takes no arguments.
        #
        # Returns nothing. (Populates cache.)
        Contract C::None => C::Any
        def validate
          # This does nothing.
        end

        # Get count of changes.
        #
        # Takes no arguments.
        #
        # Returns an Integer.
        Contract C::None => Integer
        def change_count
          super
        end

        # Calculation routines.
        #
        # Takes no arguments.
        #
        # Returns nothing (populates @actions).
        Contract C::None => C::Any
        def calculate
          # No point in calculating anything. Any references herein will be calculated automatically.
          @actions = []
        end

        # Pre-apply routines.
        #
        # Takes no arguments.
        #
        # Returns nothing.
        Contract C::None => C::Any
        def preapply
          # This does nothing.
        end

        # Apply changes.
        #
        # action - Action array.
        #
        # Returns nothing.
        Contract Entitlements::Models::Action => C::Any
        def apply(caction)
          # This does nothing.
        end

        # Validate configuration options.
        #
        # key  - String with the name of the group.
        # data - Hash with the configuration data.
        #
        # Returns nothing.
        Contract String, C::HashOf[String => C::Any] => nil
        def validate_config!(key, data)
          # Do nothing to validate. Pass whatever arguments you want, and this will just ignore them!
        end

        # :nocov:
      end
    end
  end
end
