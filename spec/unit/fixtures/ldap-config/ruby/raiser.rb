# frozen_string_literal: true

module Entitlements
  class Rule
    class Ruby
      class Raiser < Entitlements::Rule::Base
        def members
          # There is no user 'abc' defined in entitlements so this will raise a KeyError.
          Set.new(%w[abc])
        end
      end
    end
  end
end
