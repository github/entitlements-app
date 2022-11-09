# frozen_string_literal: true

require_relative "base"
require_relative "../../../../util/util"

module Entitlements
  class Data
    class Groups
      class Calculated
        class Modifiers
          class Expiration < Base
            include ::Contracts::Core
            C = ::Contracts

            # Given a set of members in a group that is being calculated, modify the
            # member set (the input) to be empty if the entitlement as a whole is expired.
            # If we do this, add the metadata that allows an empty group, assuming there
            # were in fact members in the group the first time we saw this.
            #
            # result - Set of Entitlements::Models::Person (mutated).
            #
            # Return true if we made any changes, false otherwise.
            Contract C::SetOf[Entitlements::Models::Person] => C::Bool
            def modify(result)
              return false if Entitlements.config.fetch("ignore_expirations", false)
              # If group is already empty, we have nothing to consider modifying, regardless
              # of expiration date. Just return false right away.
              if result.empty?
                return false
              end

              # If the date is in the future, leave the entitlement unchanged.
              return false if parse_date > Time.now.utc.to_date

              # Empty the group. Set metadata allowing no members. Return true to indicate modification.
              rs.metadata["no_members_ok"] = true
              result.clear
              true
            end

            private

            # Returns a date object from the configuration given to the class.
            #
            # Takes no arguments.
            #
            # Returns a date object.
            Contract C::None => Date
            def parse_date
              Entitlements::Util::Util.parse_date(config)
            end
          end
        end
      end
    end
  end
end
