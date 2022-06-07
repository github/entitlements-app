# frozen_string_literal: true
# The simplest equality check we could imagine.

module Entitlements
  class Data
    class Groups
      class Calculated
        class Rules
          class Username < Entitlements::Data::Groups::Calculated::Rules::Base
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
              # Username is easy - the value is the uid.
              begin
                Set.new([Entitlements.cache[:people_obj].read(value)].compact)
              rescue Entitlements::Data::People::NoSuchPersonError
                # We are not currently treating this as a fatal error and as such we are just
                # ignoring it. Implementors will want to implement CI-level checks for unknown
                # people if this is a concern.
                Set.new({})
              end
            end
          end
        end
      end
    end
  end
end
