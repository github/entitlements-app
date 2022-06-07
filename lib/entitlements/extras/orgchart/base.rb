# frozen_string_literal: true

require_relative "../base"
require "yaml"

module Entitlements
  module Extras
    class Orgchart
      class Base < Entitlements::Extras::Base
        def self.init
          require_relative "logic"
          require_relative "person_methods"
          require_relative "rules/direct_report"
          require_relative "rules/management"
        end

        def self.rules
          %w[direct_report management]
        end

        def self.person_methods
          %w[manager]
        end

        def self.reset!
          super
          Entitlements::Extras::Orgchart::PersonMethods.reset!
        end
      end
    end
  end
end
