# frozen_string_literal: true
module Entitlements
  class Rule
    class NestedGroups
      class Group4 < Entitlements::Rule::Base
        description "My test fixture"

        def members
          Set.new([Entitlements.cache[:people_obj].read["RAGAMUFFIn"]])
        end
      end
    end
  end
end
