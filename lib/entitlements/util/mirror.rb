# frozen_string_literal: true

module Entitlements
  class Util
    class Mirror
      include ::Contracts::Core
      C = ::Contracts

      # Validate a configuration for an OU that is a mirror. Return if the configuration
      # is valid; raise an error if it is not.
      #
      # key - A String with the key from the entitlements configuration
      #
      # Returns nothing.
      Contract String => nil
      def self.validate_mirror!(key)
        # Make sure there is not an existing file, directory, or anything else in the
        # directory structure defined by this key.
        begin
          src = Entitlements::Util::Util.path_for_group(key)
          raise ArgumentError, "#{key.inspect} is declared as a mirror OU but source #{src.inspect} exists!"
        rescue Errno::ENOENT
          # This is desired.
        end

        # Make sure the target exists.
        target = Entitlements.config["groups"][key]["mirror"]
        unless Entitlements.config["groups"].key?(target)
          raise ArgumentError, "#{key.inspect} is declared as a mirror to a non-existing target #{target.inspect}!"
        end

        # Make sure the target is not itself a mirror.
        if Entitlements.config["groups"][target]["mirror"]
          raise ArgumentError, "#{key.inspect} is declared as a mirror to a mirror target #{target.inspect}!"
        end

        # All is well
        nil
      end
    end
  end
end
