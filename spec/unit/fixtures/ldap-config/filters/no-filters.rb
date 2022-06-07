# frozen_string_literal: true
module Entitlements
  class Rule
    class Filters
      class NoFilters < Entitlements::Rule::Base
        description "No Filters"

        def members
          Set.new([cache[:people_obj].read["uid=RAGAMUFFIn,ou=People,dc=kittens,dc=net"]])
        end
      end
    end
  end
end
