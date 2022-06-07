# frozen_string_literal: true
# Helper functions to implement our own business logic.

module Entitlements
  module Extras
    class Orgchart
      class Logic
        include ::Contracts::Core
        C = ::Contracts

        # Constructor for the people logic engine. Pass in the indexed hash of people in the organization
        # and this will handle indexing, caching, and reporting relationship logic.
        #
        # people_hash - A Hash of { dn => Entitlements::Models::Person LDAP Object }
        Contract C::KeywordArgs[
          people: C::HashOf[String => Entitlements::Models::Person],
        ] => C::Any
        def initialize(people:)
          @people_hash = people.map { |uid, person| [uid.downcase, person] }.to_h
          @direct_reports_cache = nil
          @all_reports_cache = nil
        end

        # Calculate the direct reports of a given person, returning a Set of all of the people who report to
        # that person. Does NOT return the manager themselves as part of the result set. Returns an empty set
        # if the person has nobody directly reporting to them.
        #
        # manager - Entitlements::Models::Person who is the manager or higher
        #
        # Returns a Set of Entitlements::Models::Person's.
        Contract Entitlements::Models::Person => C::SetOf[Entitlements::Models::Person]
        def direct_reports(manager)
          manager_uid = manager.uid.downcase
          direct_reports_cache.key?(manager_uid) ? direct_reports_cache[manager_uid] : Set.new
        end

        # Calculate the all reports of a given person, returning a Set of all of the people who report to
        # that person directly or indirectly. Does NOT return the manager themselves as part of the result
        # set. Returns an empty set if the person has nobody reporting to them.
        #
        # manager - Entitlements::Models::Person who is the manager or higher
        #
        # Returns a Set of LDAP object Entitlements::Models::Persons.
        Contract Entitlements::Models::Person => C::SetOf[Entitlements::Models::Person]
        def all_reports(manager)
          manager_uid = manager.uid.downcase
          all_reports_cache.key?(manager_uid) ? all_reports_cache[manager_uid] : Set.new
        end

        # Calculate the management chain for the person, returning a Set of all managers in that chain all
        # the way to the top of the tree.
        #
        # person - Entitlements::Models::Person object
        #
        # Returns a Set of LDAP object openstructs.
        Contract Entitlements::Models::Person => C::SetOf[Entitlements::Models::Person]
        def management_chain(person)
          person_uid = person.uid.downcase

          @management_chain_cache ||= {}
          return @management_chain_cache[person_uid] if @management_chain_cache[person_uid].is_a?(Set)

          @management_chain_cache[person_uid] = Set.new
          if person.manager && person.manager != person.uid
            person_manager_uid = person.manager.downcase
            unless @people_hash.key?(person_manager_uid)
              # :nocov:
              raise ArgumentError, "Manager #{person.manager.inspect} for person #{person.uid.inspect} does not exist!"
              # :nocov:
            end
            # The recursive logic here will also define the management_chain_cache value for the manager,
            # and when calculating that it will define the management_chain_cache value for that manager's manager,
            # and so on. This ensures that each person's manager is only computed one time (when it's used) and
            # subsequent lookups are all faster.
            @management_chain_cache[person_uid].add @people_hash[person_manager_uid]
            @management_chain_cache[person_uid].merge management_chain(@people_hash[person_manager_uid])
          end
          @management_chain_cache[person_uid]
        end

        private

        # Iterate through the entire employee list and build up the lists of direct reports for each
        # manager. Cache this so that the iteration only occurs one time.
        #
        # Returns a Hash of { "dn" => Set(Entitlements::Models::Person) }
        Contract C::None => C::HashOf[String => C::SetOf[Entitlements::Models::Person]]
        def direct_reports_cache
          return @direct_reports_cache if @direct_reports_cache

          Entitlements.logger.debug "Building #{self.class} direct_reports_cache"

          @direct_reports_cache = {}
          @people_hash.each do |uid, entry|
            # If this person doesn't have a manager, then bail. (CEO)
            next unless entry.manager && entry.manager != entry.uid

            # Initialize their manager's list of direct reports if necessary, and add this person
            # to that list.
            person_manager_uid = entry.manager.downcase
            @direct_reports_cache[person_manager_uid] ||= Set.new
            @direct_reports_cache[person_manager_uid].add entry
          end

          Entitlements.logger.debug "Built #{self.class} direct_reports_cache"

          @direct_reports_cache
        end

        # Iterate through the list of managers and build up the lists of direct and indirect reports for each
        # manager. Cache this so that the iteration only occurs one time.
        #
        # Returns a Hash of { "dn" => Set(Entitlements::Models::Person) }
        Contract C::None => C::HashOf[String => C::SetOf[Entitlements::Models::Person]]
        def all_reports_cache
          return @all_reports_cache if @all_reports_cache

          Entitlements.logger.debug "Building #{self.class} all_reports_cache"

          @all_reports_cache = {}
          direct_reports_cache.keys.each do |manager_uid|
            generate_recursive_reports(manager_uid.downcase)
          end

          Entitlements.logger.debug "Built #{self.class} all_reports_cache"

          @all_reports_cache
        end

        # Recursive method to determine all reports (direct and indirect). Intended to be called
        # from `reports` method, when @direct_reports_cache has been populated but @all_reports_cache
        # has not yet been initialized. This will populate @all_reports_cache. This hits each manager
        # only once - O(N).
        #
        # manager_uid - A String with the uid of the manager.
        #
        # No return value.
        Contract String => nil
        def generate_recursive_reports(manager_uid)
          # If we've calculated it already, then just return early
          return if @all_reports_cache.key?(manager_uid)

          # We've visited, so start the entry for it.
          @all_reports_cache[manager_uid] = Set.new

          # Add each direct report, as well as that person's direct reports, and so on.
          direct_reports_cache[manager_uid].each do |direct_report|
            # The direct report is also an "all" report for their manager.
            @all_reports_cache[manager_uid].add direct_report
            direct_report_uid = direct_report.uid.downcase

            # If the direct report has no reports of their own, no need to go any further.
            next unless direct_reports_cache.key?(direct_report_uid)

            # Call this method again, this time with the direct report as the key. If we've already
            # calculated all descendant reports of this person, it'll return immediately. Otherwise
            # it'll iterate through this logic again, ensuring that we only calculate descendants
            # once for any given person.
            generate_recursive_reports(direct_report_uid)

            # Merge in the calculated result for all of this report's descendants.
            @all_reports_cache[manager_uid].merge @all_reports_cache[direct_report_uid]
          end

          # Satisfy the contract for return value.
          nil
        end
      end
    end
  end
end
