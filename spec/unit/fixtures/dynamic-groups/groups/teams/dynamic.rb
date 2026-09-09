# frozen_string_literal: true

module Entitlements
  class Rule
    class Teams
      class Dynamic < Entitlements::Rule::Base
        def members
          ENV.fetch("DYNAMIC_GROUP_TOKEN")
          Octokit::Client
          Entitlements::Service::GitHub
          Set.new
        end
      end
    end
  end
end
