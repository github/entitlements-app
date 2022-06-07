# frozen_string_literal: true

module Entitlements
  class Rule
    class Entitlements
      class SecurityOps < Entitlements::Rule::Base
        description "Member of the ultra-impressive and super-awesome grumpy-cat team"

        def members
          Set.new([cache[:people_obj].read["BlackManx"]])
        end
      end
    end
  end
end
