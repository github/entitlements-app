# frozen_string_literal: true

require "net/ldap"

module Entitlements
  class Service
    class LDAP
      include ::Contracts::Core
      C = ::Contracts

      class ConnectionError < RuntimeError; end
      class DuplicateEntryError < RuntimeError; end
      class EntryError < RuntimeError; end
      class WTFError < RuntimeError; end

      # We use the binddn as the owner of the group, for lack of anything better.
      # This keeps the schema happy.
      attr_reader :binddn, :person_dn_format

      # Constructor-like object that ensures only one LDAP object (and hence connection)
      # is made for a given LDAP server, for efficiency sake. Takes the same parameters as
      # the constructor and returns the same object type.
      #
      # addr   - URL of LDAP server e.g. ldaps://ldap.example.net:636
      # binddn - DN to bind with
      # bindpw - Password for the bind user
      # ca_file - Can be set to a CA certificate
      # disable_ssl_verification - Can be set to true to disable SSL verification when connecting
      #
      # Returns Entitlements::Service::LDAP object.
      Contract C::KeywordArgs[
        addr: String,
        binddn: String,
        bindpw: String,
        ca_file: C::Optional[C::Or[nil, String]],
        disable_ssl_verification: C::Optional[C::Bool],
        person_dn_format: String
      ] => Entitlements::Service::LDAP
      def self.new_with_cache(addr:, binddn:, bindpw:, ca_file: ENV["LDAP_CACERT"], disable_ssl_verification: false, person_dn_format:)
        # only look at LDAP_DISABLE_SSL_VERIFICATION in the environment if we didn't pass true to the method already
        if disable_ssl_verification == false
          # otherwise if it's set to anything at all in env, disable ssl verification
          disable_ssl_verification = !!ENV["LDAP_DISABLE_SSL_VERIFICATION"]
        end
        fingerprint = [addr, binddn, bindpw, ca_file, disable_ssl_verification, person_dn_format].map(&:inspect).join("|")
        Entitlements.cache[:ldap_connections] ||= {}
        Entitlements.cache[:ldap_connections][fingerprint] ||= new(
          addr: addr,
          binddn: binddn,
          bindpw: bindpw,
          ca_file: ca_file,
          disable_ssl_verification: disable_ssl_verification,
          person_dn_format: person_dn_format
        )
      end

      # Constructor.
      #
      # addr   - URL of LDAP server e.g. ldaps://ldap.example.net:636
      # binddn - DN to bind with
      # bindpw - Password for the bind user
      # ca_file - Can be set to a CA certificate
      # disable_ssl_verification - Can be set to true to disable SSL verification when connecting
      # person_dn_format - String template to convert a bare username to a distinguished name (`%KEY%` is replaced)
      #
      # Returns nothing.
      Contract C::KeywordArgs[
        addr: String,
        binddn: String,
        bindpw: String,
        ca_file: C::Optional[C::Or[nil, String]],
        disable_ssl_verification: C::Optional[C::Bool],
        person_dn_format: String
      ] => C::Any
      def initialize(addr:, binddn:, bindpw:, ca_file: ENV["LDAP_CACERT"], disable_ssl_verification: false, person_dn_format:)
        # Save some parameters for the LDAP connection but don't actually bind yet.
        @addr = addr
        @binddn = binddn
        @bindpw = bindpw
        @ca_file = ca_file
        @disable_ssl_verification = disable_ssl_verification
        @person_dn_format = person_dn_format
      end

      # Read a single entry identified by its DN and return the value. Returns nil if
      # the entry does not exist.
      #
      # dn - A String with the distinguished name
      #
      # Returns the Net::LDAP::Entry if it exists, nil otherwise.
      Contract String => C::Or[nil, Net::LDAP::Entry]
      def read(dn)
        @dn_cache ||= {}
        @dn_cache[dn] ||= search(base: dn, attrs: "*", scope: Net::LDAP::SearchScope_BaseObject)[dn] || :none
        @dn_cache[dn] == :none ? nil : @dn_cache[dn]
      end

      # Perform a search, iterate through each entry, and return a hash of the indexed attribute
      # to the results.
      #
      # base   - A String with the base of the search
      # filter - A Net::LDAP::Filter object with the search. Leave undefined for no filter.
      # attrs  - An Array of Strings with the attributes to retrieve. Can also be just "*".
      # index  - A String with the attribute to build the hash table on (default: dn)
      #
      # Returns a Hash of entries (entries are hashes if multiple == false, Arrays of hashes if multiple == true)
      Contract C::KeywordArgs[
        base: String,
        filter: C::Maybe[Net::LDAP::Filter],
        attrs: C::Maybe[C::Or[C::ArrayOf[String], "*"]],
        index: C::Maybe[C::Or[Symbol, String]],
        scope: C::Maybe[Integer]
      ] => C::HashOf[String => C::Or[Net::LDAP::Entry, C::ArrayOf[Net::LDAP::Entry]]]
      def search(base:, filter: nil, attrs: "*", index: :dn, scope: Net::LDAP::SearchScope_WholeSubtree)
        Entitlements.logger.debug "LDAP Search: filter=#{filter.inspect} base=#{base.inspect}"

        # Ruby downcases these in the results anyway, so just downcase everything here so it'll
        # be consistent no matter what. LDAP is case insensitive after all!
        downcased_attrs = attrs == "*" ? "*" : attrs.map { |a| a.downcase }

        result = {}
        ldap.search(base: base, filter: filter, attributes: downcased_attrs, scope: scope, return_result: false) do |entry|
          result_key = index == :dn ? entry.dn : entry[index]
          unless result_key
            raise EntryError, "#{entry.dn} has no value for #{index.inspect}"
          end

          if result.key?(result_key)
            other_entry_dn = result[result_key].dn
            raise DuplicateEntryError, "#{entry.dn} and #{other_entry_dn} have the same value of #{index} = #{result_key.inspect}"
          end

          result[result_key] = entry
        end

        Entitlements.logger.debug "Completed search: #{result.keys.size} result(s)"

        result
      end

      # Determine if an entry exists, and return true or false.
      #
      # dn - A String with the distinguished name
      #
      # Returns true if the entry exists, false otherwise.
      Contract String => C::Bool
      def exists?(dn)
        read(dn).is_a?(Net::LDAP::Entry)
      end

      # "Upsert" -- update or create an entry in LDAP.
      #
      # dn         - A String with the distinguished name
      # attributes - Hash that defines the values to be set
      #
      # Returns true if it succeeded, false if it did not.
      Contract C::KeywordArgs[
        dn: String,
        attributes: C::HashOf[String => C::Any],
      ] => C::Or[C::Bool, nil]
      def upsert(dn:, attributes:)
        # See if the object exists by searching for it. If it exists we'll get its data back as a hash. If not
        # we'll get an empty hash. Dispatch this to the create or update methods.
        read(dn) ? update(dn: dn, existing: read(dn), attributes: attributes) : create(dn: dn, attributes: attributes)
      end

      # Delete an entry in LDAP.
      #
      # dn - A String with the distinguished name
      #
      # Returns true if it succeeded, false if it did not.
      Contract String => C::Bool
      def delete(dn)
        # See if the object exists by searching for it. If it exists we'll get its data back as a hash. If not
        # we'll get an empty hash. We don't need to delete something that doesn't already exist.
        unless exists?(dn)
          Entitlements.logger.debug "Not deleting #{dn} because it does not exist"
          return true
        end

        ldap.delete(dn: dn)
        operation_result = ldap.get_operation_result
        return true if operation_result["code"] == 0
        Entitlements.logger.error "Error deleting #{dn}: #{operation_result['message']}"
        false
      end

      # Modify an entry in LDAP. Set a value of `nil` to remove the entry instead of updating it.
      #
      # dn      - A String with the distinguished name
      # updates - A Hash of { "attribute_name" => <String>|<Array>|nil }
      #
      # Returns true if it succeeded, false if it did not.
      Contract String, C::HashOf[String => C::Or[String, C::ArrayOf[String], nil]] => C::Bool
      def modify(dn, updates)
        return false unless updates.any?
        updates.each do |attr_name, val|
          operation = ""
          if val.nil?
            next if ldap.delete_attribute(dn, attr_name)
            operation = "deleting"
          else
            next if ldap.replace_attribute(dn, attr_name, val)
            operation = "modifying"
          end
          operation_result = ldap.get_operation_result
          Entitlements.logger.error "Error #{operation} attribute #{attr_name} in #{dn}: #{operation_result['message']}"
          Entitlements.logger.error "LDAP code=#{operation_result.code}: #{operation_result.error_message}"
          return false
        end
        true
      end

      private

      attr_reader :addr, :bindpw

      # The LDAP object is initialized and bound on demand the first time it's called.
      #
      # Takes no arguments.
      #
      # Returns a Net::LDAP object that is connected and bound.
      Contract C::None => Net::LDAP
      def ldap
        @ldap ||= begin
          uri = URI(addr)

          # Construct the object
          Entitlements.logger.debug "Creating connection to #{uri.host} port #{uri.port}"
          ldap_options = {
            host: uri.host,
            port: uri.port,
            auth: { method: :simple, username: binddn, password: bindpw }
          }
          if uri.scheme == "ldaps"
            ldap_options[:encryption] = {
              method: :simple_tls,
              tls_options: {
                verify_mode: @disable_ssl_verification ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
              }
            }
          end

          if @ca_file && ldap_options[:encryption].key?(:tls_options)
            ldap_options[:encryption][:tls_options][:ca_file] = @ca_file
          end

          ldap_object = Net::LDAP.new(ldap_options)
          raise WTFError, "FATAL: can't create LDAP connection object" if ldap_object.nil?

          # Bind to LDAP
          Entitlements.logger.debug "Binding with user #{binddn.inspect} with simple password authentication"
          ldap_object.bind
          operation_result = ldap_object.get_operation_result
          if operation_result["code"] != 0
            Entitlements.logger.fatal operation_result["message"]
            raise ConnectionError, "FATAL: #{operation_result['message']}"
          end
          Entitlements.logger.debug "Successfully authenticated to #{uri.host} port #{uri.port}"

          # Return the object itself
          ldap_object
        end
      end

      # Create an object that does not exist. Private method intended to be called from
      # "upsert" after determining that the object doesn't exist.
      #
      # dn         - A String with the distinguished name
      # attributes - Hash that defines the values to be set
      #
      # Returns true if success, false otherwise.
      Contract C::KeywordArgs[
        dn: String,
        attributes: C::HashOf[String => C::Any],
      ] => C::Bool
      def create(dn:, attributes:)
        ldap.add(dn: dn, attributes: attributes)
        operation_result = ldap.get_operation_result
        return true if operation_result["code"] == 0
        if operation_result["error_message"]
          Entitlements.logger.error "#{dn}: #{operation_result['code']} #{operation_result['error_message']}"
        end
        Entitlements.logger.error "Error creating #{dn} (#{attributes.inspect}): #{operation_result['message']}"
        false
      end

      # Update an existing entry. Private method intended to be called from
      # "upsert" after determining that the object does exist.
      #
      # dn         - A String with the distinguished name
      # existing   - Net::LDAP::Entry of the existing object
      # attributes - Hash that defines the values to be set
      #
      # Returns true if success, false otherwise. Returns nil if there was not actually a change.
      Contract C::KeywordArgs[
        dn: String,
        existing: Net::LDAP::Entry,
        attributes: C::HashOf[String => C::Any],
      ] => C::Or[C::Bool, nil]
      def update(dn:, existing:, attributes:)
        ops = ops_array(existing: existing, attributes: attributes)
        return if ops.empty?

        ldap.modify(dn: dn, operations: ops)
        operation_result = ldap.get_operation_result
        return true if operation_result["code"] == 0
        Entitlements.logger.error "Error modifying #{dn}: #{ops.inspect} #{operation_result['message']}"
        false
      end

      # Map a set of existing attributes and new attributes to an array of actions
      # passed to the ldap.modify method. See http://www.rubydoc.info/gems/ruby-net-ldap/Net%2FLDAP:modify.
      #
      # existing   - Net::LDAP::Entry of the existing object
      # attributes - Hash that defines the values to be set
      #
      # Returns an array of add/replace/delete.
      Contract C::KeywordArgs[
        existing: Net::LDAP::Entry,
        attributes: C::HashOf[String => C::Any]
      ] => C::ArrayOf[[Symbol, Symbol, C::Any]]
      def ops_array(existing:, attributes:)
        normalized_existing = existing.attribute_names.map do |attr_name|
          [attr_name.to_s.downcase.to_sym, existing[attr_name]]
        end.to_h

        normalized_new = attributes.map { |k, v| [k.downcase.to_sym, v] }.to_h

        all_attributes = normalized_existing.keys | normalized_new.keys

        all_attributes.map do |attr_key|
          attr_val = normalized_new[attr_key]
          if attr_val.nil?
            if normalized_existing.key?(attr_key) && normalized_new.key?(attr_key)
              # Delete existing
              [:delete, attr_key, nil]
            elsif normalized_existing.key?(attr_key)
              # Undefined in the new attributes, so ignore (will be removed by 'compact' call)
              nil
            else
              # Nothing is there to delete, so ignore (will be removed by 'compact' call)
              nil
            end
          else
            if !normalized_existing.key?(attr_key)
              # Key doesn't exist now, so this is an add
              [:add, attr_key, attr_val]
            elsif normalized_existing[attr_key].is_a?(Array) && normalized_existing[attr_key].size == 1 && normalized_existing[attr_key].first == attr_val
              # This is equivalence, so do nothing (will be removed by 'compact' call)
              nil
            elsif normalized_existing[attr_key] != attr_val
              # Replace existing
              [:replace, attr_key, attr_val]
            else
              # Unchanged, so do nothing (will be removed by 'compact' call)
              nil
            end
          end
        end.compact
      end

      # Construct an Entitlements::Models::Group from a Net::LDAP::Entry
      #
      # entry - The Net::LDAP::Entry
      #
      # Returns an Entitlements::Models::Group object.
      Contract Net::LDAP::Entry => Entitlements::Models::Group
      def self.entry_to_group(entry)
        Entitlements::Models::Group.new(
          dn: entry.dn,
          members: Set.new(member_array(entry)),
          description: entry[:description].is_a?(Array) ? entry[:description].first.to_s : ""
        )
      end

      # Convert members in a Net::LDAP::Entry to a suitable array of DNs. Has to handle `uniquemember`
      # for `groupOfUniqueNames` and `member` for `groupOfNames`.
      #
      # entry - The Net::LDAP::Entry
      #
      # Returns an Array of Strings with the first attribute (typically uid).
      Contract Net::LDAP::Entry => C::ArrayOf[String]
      def self.member_array(entry)
        members = if entry[:objectclass].include?("groupOfUniqueNames")
          entry[:uniquemember]
        elsif entry[:objectclass].include?("groupOfNames")
          entry[:member]
        elsif entry[:objectclass].include?("posixGroup")
          entry[:memberuid]
        else
          raise "Do not know how to handle objectClass = #{entry[:objectclass].inspect} for dn=#{entry.dn.inspect}!"
        end

        # If the group has itself as a member, take that out. That is a convention for the
        # Entitlements LDAP provider only which needs to be kept internal.
        members -= [entry.dn]

        members.map { |dn| Entitlements::Util::Util.first_attr(dn) }
      end
    end
  end
end
