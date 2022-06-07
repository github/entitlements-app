# frozen_string_literal: true

module Entitlements
  class Data
    class Groups
      class Calculated
        class Modifiers
          class Base
            include ::Contracts::Core
            C = ::Contracts

            # Constructor. Needs the cache (Hash with various objects of interest) for
            # future lookups.
            #
            # rs     - Entitlements::Data::Groups::Calculated::* object
            # config - Configuration for this modifier as defined in entitlement
            Contract C::KeywordArgs[
              rs: C::Or[
                Entitlements::Data::Groups::Calculated::Ruby,
                Entitlements::Data::Groups::Calculated::Text,
                Entitlements::Data::Groups::Calculated::YAML,
              ],
              config: C::Any
            ] => C::Any
            def initialize(rs:, config: nil)
              @rs = rs
              @config = config
            end

            private

            attr_reader :config, :rs
          end
        end
      end
    end
  end
end
