# frozen_string_literal: true
module Entitlements
  class Rule
    class Filters
      class TwoFiltersOneStatement < Entitlements::Rule::Base
        description "No Filters"
        filter "contractors" => :all, "pre-hires" => :all

        def members
          Set.new([cache[:people_obj].read["uid=RAGAMUFFIn,ou=People,dc=kittens,dc=net"]])
        end
      end
    end
  end
end
