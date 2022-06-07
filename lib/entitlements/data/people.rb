# frozen_string_literal: true

require_relative "people/combined"
require_relative "people/dummy"
require_relative "people/ldap"
require_relative "people/yaml"

module Entitlements
  class Data
    class People
      class NoSuchPersonError < RuntimeError; end

      include ::Contracts::Core
      C = ::Contracts

      PEOPLE_CLASSES = {
        "combined" => Entitlements::Data::People::Combined,
        "dummy"    => Entitlements::Data::People::Dummy,
        "ldap"     => Entitlements::Data::People::LDAP,
        "yaml"     => Entitlements::Data::People::YAML
      }

      # Gets the class for the specified configuration. Basically this is a wrapper around PEOPLE_CLASSES
      # with friendly error messages if a configuration is insufficient to select the class.
      #
      # config - Hash of configuration values as may be found in the Entitlements configuration file.
      #
      # Returns Entitlements::Data::People class.
      Contract C::HashOf[String => C::Any] => Class
      def self.class_for_config(config)
        unless config.key?("type")
          raise ArgumentError, "'type' is undefined in: #{config.inspect}"
        end

        unless Entitlements::Data::People::PEOPLE_CLASSES.key?(config["type"])
          raise ArgumentError, "'type' #{config['type'].inspect} is invalid!"
        end

        Entitlements::Data::People::PEOPLE_CLASSES.fetch(config["type"])
      end

      # Constructor to build an object from the configuration file. Given a key in the `groups`
      # section, check the `people` key for one or more data sources for people records. Construct
      # the underlying object(s) as necessary while caching duplicate objects.
      #
      # config - Hash of configuration values as may be found in the Entitlements configuration file.
      #
      # Returns Entitlements::Data::People object backed by appropriate object(s).
      Contract C::HashOf[String => C::Any] => C::Any
      def self.new_from_config(config)
        Entitlements.cache[:people_class] ||= {}
        clazz = class_for_config(config)
        fingerprint = clazz.fingerprint(config.fetch("config"))
        Entitlements.cache[:people_class][fingerprint] ||= clazz.new_from_config(config.fetch("config"))
      end
    end
  end
end
