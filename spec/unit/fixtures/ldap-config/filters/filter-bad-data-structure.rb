# frozen_string_literal: true
module Entitlements
  class Rule
    class Filters
      class FilterBadDataStruture < Entitlements::Rule::Base
        description "FilterBadDataStruture"

        filter "contractors" => {"foo"=>"bar", "fizz"=>"buzz"}

        def members
          Set.new([cache[:people_obj].read["uid=RAGAMUFFIn,ou=People,dc=kittens,dc=net"]])
        end
      end
    end
  end
end
