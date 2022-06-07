# frozen_string_literal: true
module Entitlements
  class Rule
    class Filters
      class MultipleContractors1 < Entitlements::Rule::Base
        description "MultipleContractors1"

        filter "contractors" => %w[pixiEBOB SErengeti]

        def members
          Set.new([cache[:people_obj].read["uid=RAGAMUFFIn,ou=People,dc=kittens,dc=net"]])
        end
      end
    end
  end
end
