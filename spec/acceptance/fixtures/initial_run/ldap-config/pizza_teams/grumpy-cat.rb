# frozen_string_literal: true
# By virtue of filename this creates cn=grumpy-cat,ou=pizza_teams,dc=kittens,dc=net

module Entitlements
  class Rule
    class PizzaTeams
      class GrumpyCat < Entitlements::Rule::Base
        description "Member of the ultra-impressive and super-awesome grumpy-cat team"

        def members
          Set.new([Entitlements.cache[:people_obj].read("BlackManx")])
        end

        def metadata
          { "foo" => "bar" }
        end
      end
    end
  end
end
