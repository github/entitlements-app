# frozen_string_literal: true

module Entitlements
  class Models
    class Person
      include ::Contracts::Core
      C = ::Contracts

      attr_reader :uid

      # Constructor.
      #
      # uid        - A String with user's ID (unique throughout Entitlements)
      # attributes - Optionally a Hash of {String => String | Array<String>} with additional attributes
      Contract C::KeywordArgs[
        uid: String,
        attributes: C::Maybe[C::HashOf[String => C::Or[String, C::ArrayOf[String], nil]]]
      ] => C::Any
      def initialize(uid:, attributes: {})
        @uid = uid
        setup_attributes(attributes)
      end

      # Grab any methods that have been defined by extras and dispatch them to the appropriate backend.
      # The first argument sent to the method is a reference to this object (self). Any arguments passed
      # by the caller are sent thereafter. For now this ignores blocks (maybe figure this out later?).
      #
      # Arguments and return varies.
      def method_missing(m, *args, &block)
        if method_class_ref = Entitlements.person_extra_methods[m]
          return method_class_ref.send(m, self, *args)
        end

        # :nocov:
        raise NoMethodError, "No method '#{m}' exists for Entitlements::Models::Person or any registered extras."
        # :nocov:
      end

      # Hash method to get current value of an attribute. Raises if the attribute is undefined.
      #
      # attribute - A String with the attribute name to retrieve.
      #
      # Returns a String or Array<String> with the attribute's value. (nil deletes later)
      Contract String => C::Or[String, C::ArrayOf[String], nil]
      def [](attribute)
        outward(@current_attributes.fetch(attribute))
      end

      # Get current value of the original attribute.
      #
      # attribute - A String with the attribute name to retrieve.
      #
      # Returns a String or Array<String> with the attribute's value. (nil if it did not exist)
      Contract String => C::Or[String, C::ArrayOf[String], nil]
      def original(attribute)
        outward(@original_attributes[attribute])
      end

      # Hash method to set current value of an attribute.
      #
      # attribute - A String with the attribute name to set.
      # val       - A String, Array<String>, Set<String>, or nil with new value. (nil deletes later)
      #
      # Returns nothing interesting (this method is in void context).
      Contract String, C::Or[String, C::ArrayOf[String], C::SetOf[String], nil] => C::Any
      def []=(attribute, val)
        @touched_attributes.add(attribute)

        if val.nil? && @original_attributes[attribute].nil?
          @original_attributes.delete(attribute)
          @current_attributes.delete(attribute)
          return
        end

        @original_attributes[attribute] ||= nil
        if val.nil? || val.is_a?(String)
          @current_attributes[attribute] = val
        elsif val.is_a?(Set)
          @current_attributes[attribute] = val.dup
        else
          @current_attributes[attribute] = Set.new(val)
        end
      end

      # Get the changes between original attributes and any attributes updated in this session.
      #
      # Takes no arguments.
      #
      # Returns a Hash of { attribute name => new value }.
      Contract C::None => C::HashOf[String => C::Or[String, C::ArrayOf[String], nil]]
      def attribute_changes
        @current_attributes
          .select { |k, _| @touched_attributes.member?(k) }
          .reject { |k, v| @original_attributes[k] == v }
          .reject { |k, v| (@original_attributes[k].nil? || @original_attributes[k] == Set.new) && (v.nil? || v == Set.new) }
          .map { |k, _| [k, self[k]] }
          .to_h
      end

      # Update an attribute that is an array or a set by adding a new string item to it.
      #
      # attribute - A String with the attribute name to set.
      # val       - A String to add to the array/set.
      #
      # Returns nothing.
      Contract String, String => nil
      def add(attribute, val)
        @touched_attributes.add(attribute)
        ca = @current_attributes.fetch(attribute) # Raises if not found
        raise ArgumentError, "Called add() on attribute that is a #{ca.class}" unless ca.is_a?(Set)
        ca.add(val)
        nil
      end

      private

      # Convert the internal structure of an attribute to the displayed structure. Basically
      # converts sets into sorted arrays and leaves everything else untouched.
      #
      # internal_obj - The internal structure.
      #
      # Returns the outward facing structure.
      Contract C::Or[nil, String, C::SetOf[String]] => C::Or[nil, String, C::ArrayOf[String]]
      def outward(internal_obj)
        internal_obj.is_a?(Set) ? internal_obj.sort : internal_obj
      end

      # Construct a hash of attributes, keeping track of the original attributes as well
      # as the current ones.
      #
      # attributes - Hash of {String => String | Array<String>} with additional attributes
      #
      # Returns nothing.
      Contract C::HashOf[String => C::Or[String, C::ArrayOf[String], nil]] => nil
      def setup_attributes(attributes)
        @touched_attributes = Set.new
        @original_attributes = {}
        @current_attributes = {}
        attributes.each do |k, v|
          next if v.nil?
          val = v.is_a?(Array) ? Set.new(v.sort) : v
          @original_attributes[k] = val.dup
          @current_attributes[k] = val.dup
        end
        nil
      end
    end
  end
end
