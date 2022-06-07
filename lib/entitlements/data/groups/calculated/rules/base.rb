# frozen_string_literal: true
# Base class for rules that we write.

module Entitlements
  class Data
    class Groups
      class Calculated
        class Rules
          class Base
            include ::Contracts::Core
            C = ::Contracts

            # Interface method: Get a Set[Entitlements::Models::Person] matching this condition.
            #
            # value  - The value to match.
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
              # :nocov:
              raise "matches() must be defined in the child class #{self.class}!"
              # :nocov:
            end
          end
        end
      end
    end
  end
end
