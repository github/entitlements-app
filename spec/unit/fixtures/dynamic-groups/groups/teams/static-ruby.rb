# frozen_string_literal: true

# Documentation may mention ENV["TOKEN"] or Net::HTTP without using either.
module Entitlements
  class Rule
    class Teams
      class StaticRuby < Entitlements::Rule::Base
        description "Does not call Octokit or Faraday"

        def members
          Set.new([Entitlements.cache[:people_obj].read("Alice")])
        end
      end
    end
  end
end
