# frozen_string_literal: true
# Is someone in a management chain?

module Entitlements
  module Extras
    class Orgchart
      class Rules
        class Management < Entitlements::Data::Groups::Calculated::Rules::Base
          include ::Contracts::Core
          C = ::Contracts

          # Interface method: Get a Set[Entitlements::Models::Person] matching this condition.
          #
          # value  - The value to match.
          # filename - Name of the file resulting in this rule being called
          # options  - Optional hash of additional method-specific options
          #
          # Returns a Set[Entitlements::Models::Person].
          Contract C::KeywordArgs[
            value: String,
            filename: C::Maybe[String],
            options: C::Optional[C::HashOf[Symbol => C::Any]]
          ] => C::SetOf[Entitlements::Models::Person]
          def self.matches(value:, filename: nil, options: {})
            begin
              manager = Entitlements.cache[:people_obj].read(value)
            rescue Entitlements::Data::People::NoSuchPersonError
              # This is fatal. If this defines a team by a manager who is no longer in LDAP then the
              # entry needs to be corrected because those people have to report to someone...
              Entitlements.logger.fatal "Manager #{value} does not exist for file #{filename}!"
              raise "Manager #{value} does not exist!"
            end

            # Call all_reports which will return the set of all direct and indirect reports.
            # This is evaluated once per run of the program.
            Entitlements.cache[:management_obj] ||= begin
              Entitlements::Extras::Orgchart::Logic.new(people: Entitlements.cache.fetch(:people_obj).read)
            end

            # This is fatal. If this defines a manager who has nobody reporting to them, then they
            # aren't a manager at all. The entry should be changed to "username" or otherwise the
            # proper manager should be filled in.
            if Entitlements.cache[:management_obj].all_reports(manager).empty?
              Entitlements.logger.fatal "Manager #{value} has no reports for file #{filename}!"
              raise "Manager #{value} has no reports!"
            end

            # Most of the time, people will expect "management: xyz" to include xyz and anyone who
            # reports to them. Technically, xyz doesn't report to themself, but we'll hack it in here
            # because it's least surprise. If someone really wants "xyz's reports but not xyz" they
            # can use the "not" in conjunction.
            result = Set.new([manager])
            result.merge Entitlements.cache[:management_obj].all_reports(manager)
          end
        end
      end
    end
  end
end
