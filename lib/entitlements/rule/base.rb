# frozen_string_literal: true

# Rules written in ruby can (and should) inherit this class.

module Entitlements
  class Rule
    class Base
      include ::Contracts::Core
      C = ::Contracts

      # This method must be re-implemented by the child class.
      #
      # Takes no Arguments.
      #
      # Returns a Set[String] of the DN's of all people who satisfy the filter.
      Contract C::None => C::SetOf[String]
      def members
        # :nocov:
        raise "Must be implemented by the child class"
        # :nocov:
      end

      # This method allows the class to contain a line like:
      #   description "This is some text"
      # and have that description be set as a class variable. When
      # called without an argument, this returns the value of the
      # description, so the instance can access it.
      Contract C::Maybe[String] => String
      def self.description(text = nil)
        if text
          @description = text
        else
          @description ||= ""
        end
      end

      # Retrieve the description of the group from the class variable.
      #
      # Takes no arguments.
      #
      # Returns a String with the description.
      Contract C::None => String
      def description
        self.class.description
      end

      # This method allows the class to contain a line like:
      #   filter "foo" => :all / :none / [list of Strings]
      # and have that filter be set as a class variable. When
      # called without an argument, this returns the value of the
      # filter, so the instance can access it.
      Contract C::Maybe[C::HashOf[String => C::Or[:all, :none, C::ArrayOf[String]]]] => C::HashOf[String => C::Or[:all, :none, C::ArrayOf[String]]]
      def self.filter(filter_pair = nil)
        @filters ||= Entitlements::Data::Groups::Calculated.filters_default
        @filters.merge!(filter_pair) if filter_pair
        @filters
      end

      # Retrieve the filters for the group from the class variable.
      #
      # Takes no arguments.
      #
      # Returns a Hash with the filters.
      Contract C::None => C::HashOf[String => C::Or[:all, :none, C::ArrayOf[String]]]
      def filters
        self.class.filter
      end

      private

      attr_reader :cache
    end
  end
end
