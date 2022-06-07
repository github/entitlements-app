# frozen_string_literal: true

# Supports predictive entitlements updates. This looks for the believed-to-be-true current membership of groups
# in a directory of flat files, so as to speed things up by not calling slower APIs. If the calculated membership
# is not equal to the flat files, then the membership should be recomputed by contacting the API.
#
# Reading in cached groups from the supplied directory is global across the entire entitlements system,
# so this is a singleton class.

module Entitlements
  class Data
    class Groups
      class Cached
        include ::Contracts::Core
        C = ::Contracts

        # Load the caches - read files from dir and populate
        # Entitlements.cache[:predictive_state] for later use. This should only be done once per run.
        #
        # dir - Directory containing the cache.
        #
        # Returns nothing.
        Contract String => nil
        def self.load_caches(dir)
          unless File.directory?(dir)
            raise Errno::ENOENT, "Predictive state directory #{dir.inspect} does not exist!"
          end

          Entitlements.logger.debug "Loading predictive update caches from #{dir}"

          Entitlements.cache[:predictive_state] = { by_ou: {}, by_dn: {}, invalid: Set.new }

          Dir.glob(File.join(dir, "*")).each do |filename|
            dn = File.basename(filename)
            identifier, ou = dn.split(",", 2)

            file_lines = File.readlines(filename).map(&:strip).map(&:downcase).compact

            members = file_lines.dup
            members.reject! { |line| line.start_with?("#") }
            members.reject! { |line| line.start_with?("metadata_") }
            member_set = Set.new(members)

            metadata = file_lines.dup
            unless metadata.empty?
              metadata.select! { |line| line.start_with?("metadata_") }
              metadata = metadata.map { |metadata_string| metadata_string.split "=" }.to_h
              metadata.transform_keys! { |key| key.delete_prefix("metadata_") }
            end

            Entitlements.cache[:predictive_state][:by_ou][ou] ||= {}
            Entitlements.cache[:predictive_state][:by_ou][ou][identifier] = member_set
            Entitlements.cache[:predictive_state][:by_dn][dn] = { members: member_set, metadata: metadata }
          end

          Entitlements.logger.debug "Loaded #{Entitlements.cache[:predictive_state][:by_ou].keys.size} OU(s) from cache"
          Entitlements.logger.debug "Loaded #{Entitlements.cache[:predictive_state][:by_dn].keys.size} DN(s) from cache"

          nil
        end

        # Invalidate a particular cache entry.
        #
        # dn - A String with the cache entry to invalidate.
        #
        # Returns nothing.
        Contract String => nil
        def self.invalidate(dn)
          return unless Entitlements.cache[:predictive_state]
          Entitlements.cache[:predictive_state][:invalid].add(dn)
          nil
        end

        # Get a list of members from a particular cached entry.
        #
        # dn - A String with the distinguished name
        #
        # Returns an Set of Strings, or nil if the DN is not in the cache or is invalid.
        Contract String => C::Or[C::SetOf[String], nil]
        def self.members(dn)
          return unless Entitlements.cache[:predictive_state]

          if Entitlements.cache[:predictive_state][:invalid].member?(dn)
            Entitlements.logger.debug "members(#{dn}): DN has been marked invalid in cache"
            return
          end

          unless Entitlements.cache[:predictive_state][:by_dn].key?(dn)
            Entitlements.logger.debug "members(#{dn}): DN does not exist in cache"
            return
          end

          Entitlements.cache[:predictive_state][:by_dn][dn][:members]
        end

        # Get the metadata from a particular cached entry.
        #
        # dn - A String with the distinguished name
        #
        # Returns a Hash of metadata, or nil if the DN is not in the cache, is invalid, or if there is no metadata
        Contract String => C::Or[C::HashOf[String => C::Any], nil]
        def self.metadata(dn)
          return unless Entitlements.cache[:predictive_state]

          if Entitlements.cache[:predictive_state][:invalid].member?(dn)
            Entitlements.logger.debug "metadata(#{dn}): DN has been marked invalid in cache"
            return
          end

          unless Entitlements.cache[:predictive_state][:by_dn].key?(dn)
            Entitlements.logger.debug "metadata(#{dn}): DN does not exist in cache"
            return
          end

          Entitlements.cache[:predictive_state][:by_dn][dn][:metadata]
        end
      end
    end
  end
end
