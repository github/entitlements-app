# frozen_string_literal: true
# By virtue of filename this creates cn=grumpy-cat,ou=pizza_teams,dc=kittens,dc=net

module Entitlements
  class Rule
    class Metadata
      class Good < Entitlements::Rule::Base
        def members
          Set.new([cache[:people_obj].read["uid=BlackManx,ou=People,dc=kittens,dc=net"]])
        end

        def metadata
          { "kittens" => "awesome", "puppies" => "young dogs" }
        end
      end
    end
  end
end
