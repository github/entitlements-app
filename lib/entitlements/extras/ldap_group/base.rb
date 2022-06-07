# frozen_string_literal: true

require_relative "../base"

module Entitlements
  module Extras
    class LDAPGroup
      class Base < Entitlements::Extras::Base
        def self.init
          require_relative "filters/member_of_ldap_group"
          require_relative "rules/ldap_group"
        end

        def self.rules
          %w[ldap_group]
        end
      end
    end
  end
end
