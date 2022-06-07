# frozen_string_literal: true

module Entitlements
  class Models
    class Group
      include ::Contracts::Core
      C = ::Contracts

      class NoMembers < RuntimeError; end
      class NoMetadata < RuntimeError; end

      attr_reader :dn

      # ------------------------------------------------------
      # Constructor
      # ------------------------------------------------------

      # Constructor.
      #
      # dn          - A String with the DN of the group
      # members     - A Set of Strings with the user IDs, or Entitlements::Models::Person, of the members
      # description - Optionally, a String with a description
      # metadata    - Optionally, a Hash with [String => Object] metadata
      Contract C::KeywordArgs[
        dn: String,
        members: C::SetOf[C::Or[Entitlements::Models::Person, String]],
        description: C::Maybe[String],
        metadata: C::Maybe[C::HashOf[String => C::Any]]
      ] => C::Any
      def initialize(dn:, members:, description: nil, metadata: nil)
        @dn = dn
        set_members(members)
        @description = description == [] ? "" : description
        @metadata = metadata
      end

      # Constructor to copy another group object with a different DN.
      #
      # dn - The DN for the new group (must be != the DN for the source group)
      #
      # Returns Entitlements::Models::Group object.
      Contract String => Entitlements::Models::Group
      def copy_of(dn)
        self.class.new(dn: dn, members: members.dup, description: description, metadata: metadata.dup)
      end

      # ------------------------------------------------------
      # Tell us more about this group
      # ------------------------------------------------------

      # Description must be a string and cannot be empty. If description is empty just return
      # the cn instead.
      #
      # Takes no arguments.
      #
      # Returns a non-empty string with the description.
      Contract C::None => String
      def description
        return cn if @description.nil? || @description.empty?
        @description
      end

      # Retrieve the members as a consistent object type (we'll pick Entitlements::Models::Person).
      #
      # people_obj  - Entitlements::Data::People::* Object (required if not initialized with Entitlements::Models::Person's)
      #
      # Returns Set[Entitlements::Models::Person].
      Contract C::KeywordArgs[
        people_obj: C::Maybe[C::Any]
      ] => C::SetOf[Entitlements::Models::Person]
      def members(people_obj: nil)
        result = Set.new(
          @members.map do |member|
            if member.is_a?(Entitlements::Models::Person)
              member
            elsif people_obj.nil?
              nil
            elsif people_obj.read.key?(member)
              people_obj.read(member)
            else
              nil
            end
          end.compact
        )

        return result if result.any? || no_members_ok?
        raise NoMembers, "The group #{dn} has no members!"
      end

      # Retrieve the members as a string of DNs. This is a way to avoid converting to person objects if
      # we don't need to do that anyway.
      #
      # Takes no arguments.
      #
      # Returns Set[String].
      Contract C::None => C::SetOf[String]
      def member_strings
        @member_strings ||= begin
          result = Set.new(@members.map { |member| member.is_a?(Entitlements::Models::Person) ? member.uid : member })
          if result.empty? && !no_members_ok?
            raise NoMembers, "The group #{dn} has no members!"
          end
          result
        end
      end

      # Retrieve the members as a string of DNs, case-insensitive.
      #
      # Takes no arguments.
      #
      # Returns Set[String].
      def member_strings_insensitive
        @member_strings_insensitive ||= Set.new(member_strings.map(&:downcase))
      end

      # Determine if the given person is a member of the group.
      #
      # person - A Entitlements::Models::Person object
      #
      # Returns true if the person is a direct member of the group, false otherwise.
      Contract C::Or[String, Entitlements::Models::Person] => C::Bool
      def member?(person)
        member_strings_insensitive.member?(any_to_uid(person).downcase)
      end

      # Get the CN of the group (extracted from the DN).
      #
      # Takes no arguments.
      #
      # Returns a String with the CN.
      Contract C::None => String
      def cn
        return Regexp.last_match(1) if dn =~ /\Acn=(.+?),/
        raise "Could not determine CN from group DN #{dn.inspect}!"
      end

      # Retrieve the metadata, raising an error if no metadata was set.
      #
      # Takes no arguments.
      #
      # Returns a Hash with the metadata.
      Contract C::None => C::HashOf[String => C::Any]
      def metadata
        return @metadata if @metadata
        raise NoMetadata, "Group #{dn} was not constructed with metadata!"
      end

      # Determine if this group is equal to another Entitlements::Models::Group object.
      #
      # other_group - An Entitlements::Models::Group that is being evaluated against this one.
      #
      # Return true if the contents are equivalent, false otherwise.
      Contract C::Or[Entitlements::Models::Person, Entitlements::Models::Group, :none] => C::Bool
      def equals?(other_group)
        unless other_group.is_a?(Entitlements::Models::Group)
          return false
        end

        unless dn == other_group.dn
          return false
        end

        unless description == other_group.description
          return false
        end

        unless member_strings == other_group.member_strings
          return false
        end

        true
      end

      alias_method :==, :equals?

      # Retrieve a key from the metadata if the metadata is defined. Return nil if
      # metadata wasn't defined. Don't raise an error.
      #
      # key - A String with the metadata key to retrieve.
      #
      # Returns the value of the metadata key or nil.
      Contract String => C::Any
      def metadata_fetch_if_exists(key)
        return unless @metadata.is_a?(Hash)
        @metadata[key]
      end

      # Determine if it's OK for the group to have no members. This is based on metadata, and defaults
      # to true (it's OK to have no members). This can be overridden by setting metadata to false explicitly.
      #
      # Takes no arguments.
      #
      # Returns false if no_members_ok is explicitly set to false. Returns true otherwise.
      Contract C::None => C::Bool
      def no_members_ok?
        ![false, "false"].include?(metadata_fetch_if_exists("no_members_ok"))
      end

      # Directly manipulate members. This sets the group membership directly to the specified value with no
      # verification or validation. Be very careful!
      #
      # members - A Set of Strings with the DNs, or Entitlements::Models::Person, of the members
      #
      # Returns nothing.
      Contract C::SetOf[C::Or[Entitlements::Models::Person, String]] => nil
      def set_members(members)
        @members = members
        @member_strings = nil
        @member_strings_insensitive = nil
      end

      # Add a person to the member list of the group.
      #
      # person - Entitlements::Models::Person object.
      #
      # Returns nothing.
      Contract C::Or[String, Entitlements::Models::Person] => nil
      def add_member(person)
        @members.add(person)

        # Clear these so they will be recomputed
        @member_strings = nil
        @member_strings_insensitive = nil
      end

      # Remove a person from the member list of the group. This can act either on a person object
      # or a distinguished name.
      #
      # person - Entitlements::Models::Person object or String with distinguished name.
      #
      # Returns nothing.
      Contract C::Or[Entitlements::Models::Person, String] => nil
      def remove_member(person)
        person_uid = any_to_uid(person).downcase
        @members.delete_if { |member| any_to_uid(member).downcase == person_uid }

        # Clear these so they will be recomputed
        @member_strings = nil
        @member_strings_insensitive = nil
      end

      # Update the case of a member's distinguished name, if that person is a member of this group.
      #
      # person - Entitlements::Models::Person object or String with distinguished name (with the desired case).
      #
      # Returns true if a change was made, false if not. (Also returns false if the member isn't in the group.)
      Contract C::Or[Entitlements::Models::Person, String] => C::Bool
      def update_case(person)
        person_uid = any_to_uid(person)
        downcased_dn = person_uid.downcase

        the_member = @members.find { |member| any_to_uid(member).downcase == downcased_dn }
        return false unless the_member
        return false if any_to_uid(the_member) == person_uid

        remove_member(person_uid)
        add_member(person_uid)
        true
      end

      private

      # Get a distinguished name from a String or an Entitlements::Models::Person object.
      #
      # obj - A String (with DN) or Entitlements::Models::Person
      #
      # Returns a String with the distinguished name.
      Contract C::Any => String
      def any_to_uid(obj)
        if obj.is_a?(String)
          return obj
        elsif obj.is_a?(Entitlements::Models::Person)
          return obj.uid
        else
          raise ArgumentError, "any_to_uid cannot handle #{obj.class}"
        end
      end
    end
  end
end
