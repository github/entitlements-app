# frozen_string_literal: true
# By virtue of filename this creates cn=grumpy-cat,ou=pizza_teams,dc=kittens,dc=net

module Entitlements
  class Rule
    class Metadata
      class Undefined < Entitlements::Rule::Base
        def members
          Set.new([cache[:people_obj].read["uid=BlackManx,ou=People,dc=kittens,dc=net"]])
        end
      end
    end
  end
end
