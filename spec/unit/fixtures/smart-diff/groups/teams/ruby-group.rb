# frozen_string_literal: true

module Entitlements
  class Rule
    class Teams
      class RubyGroup < Entitlements::Rule::Base
        description "Ruby membership"

        def members
          Set.new([Entitlements.cache[:people_obj].read("ALICE")])
        end
      end
    end
  end
end
