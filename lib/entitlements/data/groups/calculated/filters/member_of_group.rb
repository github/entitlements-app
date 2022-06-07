# frozen_string_literal: true

# Filter class to remove members of a particular Entitlements-managed group.

module Entitlements
  class Data
    class Groups
      class Calculated
        class Filters
          class MemberOfGroup < Entitlements::Data::Groups::Calculated::Filters::Base
            include ::Contracts::Core
            C = ::Contracts

            # Determine if the member is filtered as per this definition. Return true if the member
            # is to be filtered out, false if the member does not match the filter.
            #
            # member - Entitlements::Models::Person object
            #
            # Returns true if the person is to be filtered out, false otherwise.
            Contract Entitlements::Models::Person => C::Bool
            def filtered?(member)
              return false if filter == :all
              return false unless member_of_named_group?(member, config.fetch("group"))
              return true if filter == :none
              !member_of_filter?(member)
            end
          end
        end
      end
    end
  end
end
