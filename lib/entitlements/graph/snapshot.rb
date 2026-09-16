# frozen_string_literal: true

# Builds a serializable, backend-agnostic representation of the graph that Entitlements
# computed during this run: the group and person nodes, the membership edges between them,
# the group-to-group dependency edges, and the actions taken during the run.
#
# This class intentionally knows nothing about the storage format. It produces plain Ruby
# data structures, sorted deterministically, which a writer (such as
# Entitlements::Graph::SQLiteWriter) turns into a queryable artifact.

require "json"
require "set"

require_relative "../../version"

module Entitlements
  class Graph
    class Snapshot
      include ::Contracts::Core
      C = ::Contracts

      # Bump this whenever the structure of the emitted data changes in a way that
      # consumers need to know about.
      SCHEMA_VERSION = 1

      # Metadata key that Entitlements uses to record the file a group was calculated from.
      FILENAME_METADATA_KEY = "_filename"

      attr_reader :run, :people, :person_attributes, :ous, :groups, :group_metadata,
                  :memberships, :dependencies, :actions, :action_members

      # Constructor.
      #
      # actions            - An Array of Entitlements::Models::Action from this run.
      # successful_actions - A Set of Strings with the DNs of actions that were applied.
      # person_attributes  - An Array of Strings with the person attributes to include.
      # provider_exception - The exception raised by a provider during this run, if any.
      Contract C::KeywordArgs[
        actions: C::Optional[C::ArrayOf[Entitlements::Models::Action]],
        successful_actions: C::Optional[C::Or[C::SetOf[String], C::ArrayOf[String]]],
        person_attributes: C::Optional[C::ArrayOf[String]],
        provider_exception: C::Optional[C::Or[nil, Exception]]
      ] => C::Any
      def initialize(actions: [], successful_actions: Set.new, person_attributes: [], provider_exception: nil)
        @actions_input = actions
        @successful_actions = Set.new(successful_actions.to_a)
        @person_attribute_names = person_attributes.sort.uniq
        @provider_exception = provider_exception

        @ous = []
        @groups = []
        @group_metadata = []
        @memberships = []
        @dependencies = []
        @people = []
        @person_attributes = []
        @actions = []
        @action_members = []

        @dn_by_reference = {}

        build_run
        build_groups
        build_people
        build_dependencies
        build_actions
      end

      private

      # Populate the single row of run-level metadata.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => C::Any
      def build_run
        @run = {
          "generated_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "entitlements_version" => Entitlements::Version::VERSION,
          "schema_version" => SCHEMA_VERSION,
          "configuration_path" => Entitlements.config_path,
          "provider_exception" => @provider_exception ? "#{@provider_exception.class}: #{@provider_exception.message}" : nil
        }
      end

      # Populate the OU, group, group metadata, and membership structures from the groups
      # that Entitlements calculated during this run.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => C::Any
      def build_groups
        Entitlements::Data::Groups::Calculated.all_groups.sort.each do |ou_key, data|
          @ous << {
            "ou_key" => ou_key,
            "base_dn" => data[:config]["base"],
            "type" => data[:config]["type"]
          }

          data[:groups].sort.each do |dn, group|
            filename = group.metadata_fetch_if_exists(FILENAME_METADATA_KEY)

            @groups << {
              "dn" => dn,
              "cn" => group.cn,
              "ou_key" => ou_key,
              "description" => group.description,
              "filename" => filename
            }

            @dn_by_reference["#{ou_key}/#{group.cn}"] = dn

            metadata_for(group).sort.each do |key, value|
              next if key == FILENAME_METADATA_KEY
              @group_metadata << { "dn" => dn, "key" => key, "value" => stringify(value) }
            end

            member_strings_for(group).sort.each do |uid|
              @memberships << { "group_dn" => dn, "uid" => uid }
            end
          end
        end
      end

      # Populate the person and person attribute structures. People are sourced from the
      # people data source when it is available, and are supplemented by anyone who is
      # referenced as a member of a group.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => C::Any
      def build_people
        people_objects = {}

        people_obj = Entitlements.cache[:people_obj]
        people_obj.read.each { |uid, person| people_objects[uid] = person } if people_obj

        uids = Set.new(people_objects.keys)
        @memberships.each { |membership| uids.add(membership["uid"]) }

        uids.sort.each do |uid|
          @people << { "uid" => uid }

          person = people_objects[uid]
          next if person.nil?

          @person_attribute_names.each do |attribute|
            Array(attribute_value(person, attribute)).sort.each do |value|
              @person_attributes << { "uid" => uid, "name" => attribute, "value" => value }
            end
          end
        end
      end

      # Populate the group-to-group dependency edges that were recorded during calculation.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => C::Any
      def build_dependencies
        recorded = Entitlements.cache[:group_dependencies] || Set.new

        recorded.to_a.sort.each do |parent_reference, child_reference|
          @dependencies << {
            "parent_reference" => parent_reference,
            "child_reference" => child_reference,
            "parent_dn" => @dn_by_reference[parent_reference],
            "child_dn" => @dn_by_reference[child_reference]
          }
        end
      end

      # Populate the action and action member structures, which turn the snapshot into a
      # record of what changed during this run.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => C::Any
      def build_actions
        @actions_input.sort_by { |action| [action.ou, action.dn] }.each do |action|
          next unless action.updated.nil? || action.updated.is_a?(Entitlements::Models::Group)

          existing_members = action.existing.is_a?(Entitlements::Models::Group) ? member_strings_for(action.existing) : Set.new
          updated_members = action.updated.is_a?(Entitlements::Models::Group) ? member_strings_for(action.updated) : Set.new

          @actions << {
            "dn" => action.dn,
            "ou_key" => action.ou,
            "change_type" => action.change_type.to_s,
            "applied" => @successful_actions.member?(action.dn) ? 1 : 0
          }

          (updated_members - existing_members).sort.each do |uid|
            @action_members << { "dn" => action.dn, "uid" => uid, "change_type" => "add" }
          end

          (existing_members - updated_members).sort.each do |uid|
            @action_members << { "dn" => action.dn, "uid" => uid, "change_type" => "remove" }
          end
        end
      end

      # Get the members of a group, tolerating groups that legitimately have no members.
      #
      # group - An Entitlements::Models::Group object.
      #
      # Returns a Set of Strings with the member UIDs.
      Contract Entitlements::Models::Group => C::SetOf[String]
      def member_strings_for(group)
        group.member_strings
      rescue Entitlements::Models::Group::NoMembers
        Set.new
      end

      # Get the metadata of a group, tolerating groups that were built without metadata.
      #
      # group - An Entitlements::Models::Group object.
      #
      # Returns a Hash with the metadata.
      Contract Entitlements::Models::Group => C::HashOf[String => C::Any]
      def metadata_for(group)
        group.metadata
      rescue Entitlements::Models::Group::NoMetadata
        {}
      end

      # Get the value of a person's attribute, tolerating attributes the person does not have.
      #
      # person    - An Entitlements::Models::Person object.
      # attribute - A String with the attribute name.
      #
      # Returns a String, an Array of Strings, or nil.
      Contract Entitlements::Models::Person, String => C::Or[String, C::ArrayOf[String], nil]
      def attribute_value(person, attribute)
        person[attribute]
      rescue KeyError
        nil
      end

      # Convert an arbitrary metadata value to a String. Non-scalar values are JSON encoded
      # so that they remain machine readable (and queryable with the SQLite JSON functions).
      #
      # value - An Object of any type.
      #
      # Returns a String.
      Contract C::Any => String
      def stringify(value)
        case value
        when String then value
        when Symbol then value.to_s
        when Numeric, TrueClass, FalseClass then value.to_s
        when NilClass then ""
        when Set then JSON.generate(value.to_a)
        else JSON.generate(value)
        end
      end
    end
  end
end
