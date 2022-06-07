# frozen_string_literal: true
# Is someone in an LDAP group?

module Entitlements
  module Extras
    class LDAPGroup
      class Rules
        class LDAPGroup < Entitlements::Data::Groups::Calculated::Rules::Base
          include ::Contracts::Core
          C = ::Contracts

          # Interface method: Get a Set[Entitlements::Models::Person] matching this condition.
          #
          # value    - The value to match.
          # filename - Name of the file resulting in this rule being called
          # options  - Optional hash of additional method-specific options
          #
          # Returns a Set[Entitlements::Models::Person].
          Contract C::KeywordArgs[
            value: String,
            filename: C::Maybe[String],
            options: C::Optional[C::HashOf[Symbol => C::Any]]
          ] => C::SetOf[Entitlements::Models::Person]
          def self.matches(value:, filename: nil, options: {})
            Entitlements.cache[:ldap_cache] ||= {}
            Entitlements.cache[:ldap_cache][value] ||= begin
              entry = ldap.read(value)
              unless entry
                message = if filename
                  "Failed to read ldap_group = #{value} (referenced in #{filename})"
                else
                  # :nocov:
                  "Failed to read ldap_group = #{value}"
                  # :nocov:
                end
                raise Entitlements::Data::Groups::GroupNotFoundError, message
              end
              Entitlements::Service::LDAP.entry_to_group(entry)
            end
            Entitlements.cache[:ldap_cache][value].members(people_obj: Entitlements.cache[:people_obj])
          end

          # Object to communicate with an LDAP backend.
          #
          # Takes no arguments.
          #
          # Returns a Entitlements::Service::LDAP object.
          # :nocov:
          Contract C::None => Entitlements::Service::LDAP
          def self.ldap
            @ldap ||= begin
              config = Entitlements::Extras::LDAPGroup::Base.config
              opts = {
                addr: config.fetch("ldap_uri"),
                binddn: config.fetch("ldap_binddn"),
                bindpw: config.fetch("ldap_bindpw"),
                ca_file: config.fetch("ldap_ca_file", ENV["LDAP_CACERT"]),
                person_dn_format: config.fetch("person_dn_format")
              }
              opts[:disable_ssl_verification] = true if config.fetch("disable_ssl_verification", false)
              Entitlements::Service::LDAP.new_with_cache(opts)
            end
          end
          # :nocov:
        end
      end
    end
  end
end
