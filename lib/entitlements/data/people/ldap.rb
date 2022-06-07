# frozen_string_literal: true

require "net/ldap"

module Entitlements
  class Data
    class People
      class LDAP
        include ::Contracts::Core
        C = ::Contracts

        # Default attributes
        PEOPLE_ATTRIBUTES = %w[cn]
        UID_ATTRIBUTE = "uid"

        # Parameters
        PARAMETERS = {
          "base"                     => { required: true, type: String },
          "ldap_binddn"              => { required: true, type: String },
          "ldap_bindpw"              => { required: true, type: String },
          "ldap_uri"                 => { required: true, type: String },
          "ldap_ca_file"             => { required: false, type: String },
          "person_dn_format"         => { required: true, type: String },
          "disable_ssl_verification" => { required: false, type: [FalseClass, TrueClass] },
          "additional_attributes"    => { required: false, type: Array },
          "uid_attribute"            => { required: false, type: String }
        }

        # Fingerprint for the object based on unique parameters from the group configuration. If the fingerprint
        # matches the same object should be re-used. This will raise an error if insufficient configuration is
        # given.
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns a String with the "fingerprint" for this configuration.
        Contract C::HashOf[String => C::Any] => String
        def self.fingerprint(config)
          PARAMETERS.keys.map { |key| config[key].inspect }.join("||")
        end

        # Construct this object based on parameters in a group configuration. This is the direct translation
        # between the Entitlements configuration file (which is always a Hash with configuration values) and
        # the object constructed from this class (which can have whatever structure makes sense).
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns Entitlements::Data::People::LDAP object.
        # :nocov:
        Contract C::HashOf[String => C::Any] => Entitlements::Data::People::LDAP
        def self.new_from_config(config)
          new(
            ldap: Entitlements::Service::LDAP.new_with_cache(
              addr: config.fetch("ldap_uri"),
              binddn: config.fetch("ldap_binddn"),
              bindpw: config.fetch("ldap_bindpw"),
              ca_file: config.fetch("ldap_ca_file", ENV["LDAP_CACERT"]),
              disable_ssl_verification: config.fetch("ldap_disable_ssl_verification", false),
              person_dn_format: config.fetch("person_dn_format")
            ),
            people_ou: config.fetch("base"),
            uid_attr: config.fetch("uid_attribute", UID_ATTRIBUTE),
            people_attr: config.fetch("additional_attributes", PEOPLE_ATTRIBUTES)
          )
        end
        # :nocov:

        # Validate configuration options.
        #
        # key    - String with the name of the data source.
        # config - Hash with the configuration data.
        #
        # Returns nothing.
        # :nocov:
        Contract String, C::HashOf[String => C::Any] => nil
        def self.validate_config!(key, config)
          text = "LDAP people configuration for data source #{key.inspect}"
          Entitlements::Util::Util.validate_attr!(PARAMETERS, config, text)
        end
        # :nocov:

        # Constructor.
        #
        # ldap        - Entitlements::Service::LDAP object
        # people_ou   - String containing the OU in which people reside
        # dn_format   - How to translate a UID to a DN (e.g. uid=%KEY%,ou=People,dc=kittens,dc=net)
        # uid_attr    - Optional String with attribute name for the user ID (default: uid)
        # people_attr - Optional Array of Strings attributes of people that should be fetched from LDAP
        Contract C::KeywordArgs[
          ldap: Entitlements::Service::LDAP,
          people_ou: String,
          uid_attr: C::Maybe[String],
          people_attr: C::Maybe[C::ArrayOf[String]]
        ] => C::Any
        def initialize(ldap:, people_ou:, uid_attr: UID_ATTRIBUTE, people_attr: PEOPLE_ATTRIBUTES)
          @ldap = ldap
          @people_ou = people_ou
          @uid_attr = uid_attr
          @people_attr = people_attr
        end

        # Read in the people from LDAP. Cache result for later access.
        #
        # uid - Optionally a uid to return. If not specified, returns the entire hash.
        #
        # Returns Hash of { uid => Entitlements::Models::Person } or one Entitlements::Models::Person.
        Contract C::Maybe[String] => C::Or[C::HashOf[String => Entitlements::Models::Person], Entitlements::Models::Person]
        def read(uid = nil)
          @people ||= begin
            Entitlements.logger.debug "Loading people from LDAP"
            ldap.search(base: people_ou, filter: Net::LDAP::Filter.eq(uid_attr, "*"), attrs: people_attr.sort)
              .map { |person_dn, entry| [Entitlements::Util::Util.first_attr(person_dn).downcase, entry_to_person(entry)] }
              .to_h
          end

          return @people if uid.nil?
          return @people[uid.downcase] if @people[uid.downcase]
          raise Entitlements::Data::People::NoSuchPersonError, "read(#{uid.inspect}) matched no known person"
        end

        private

        attr_reader :ldap, :people_ou, :uid_attr, :people_attr

        # Construct an Entitlements::Models::Person from a Net::LDAP::Entry
        #
        # entry - The Net::LDAP::Entry
        #
        # Returns an Entitlements::Models::Person object.
        Contract Net::LDAP::Entry => Entitlements::Models::Person
        def entry_to_person(entry)
          attributes = people_attr
            .map { |k| [k.to_s, entry[k.to_sym]] }
            .to_h
          Entitlements::Models::Person.new(
            uid: Entitlements::Util::Util.first_attr(entry.dn),
            attributes: attributes
          )
        end
      end
    end
  end
end
