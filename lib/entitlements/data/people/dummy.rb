# frozen_string_literal: true

module Entitlements
  class Data
    class People
      class Dummy
        include ::Contracts::Core
        C = ::Contracts

        # :nocov:

        # Fingerprint for the object based on unique parameters from the group configuration. If the fingerprint
        # matches the same object should be re-used. This will raise an error if insufficient configuration is
        # given.
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns a String with the "fingerprint" for this configuration.
        Contract C::HashOf[String => C::Any] => String
        def self.fingerprint(_config)
          "dummy"
        end

        # Construct this object based on parameters in a group configuration. This is the direct translation
        # between the Entitlements configuration file (which is always a Hash with configuration values) and
        # the object constructed from this class (which can have whatever structure makes sense).
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns Entitlements::Data::People::LDAP object.
        Contract C::HashOf[String => C::Any] => Entitlements::Data::People::Dummy
        def self.new_from_config(_config)
          new
        end

        # Validate configuration options.
        #
        # key    - String with the name of the data source.
        # config - Hash with the configuration data.
        #
        # Returns nothing.
        Contract String, C::HashOf[String => C::Any] => nil
        def self.validate_config!(_key, _config)
          # This is always valid.
        end

        # Constructor.
        #
        # Takes no arguments.
        Contract C::None => C::Any
        def initialize
          # This is pretty boring.
        end

        # This would normally read in all people and then return the hash or a specific person.
        # In this case the hash is empty and there are no people.
        #
        # dn - Optionally a DN to return. If not specified, returns the entire hash.
        #
        # Returns empty hash or raises an error.
        Contract C::Maybe[String] => C::Or[C::HashOf[String => Entitlements::Models::Person], Entitlements::Models::Person]
        def read(dn = nil)
          return {} if dn.nil?
          raise Entitlements::Data::People::NoSuchPersonError, "read(#{dn.inspect}) matched no known person"
        end

        # :nocov:
      end
    end
  end
end
