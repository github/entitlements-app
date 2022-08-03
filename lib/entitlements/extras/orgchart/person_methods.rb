# frozen_string_literal: true

require_relative "../base"
require "yaml"

module Entitlements
  module Extras
    class Orgchart
      class PersonMethods < Entitlements::Extras::Orgchart::Base
        include ::Contracts::Core
        C = ::Contracts

        # This method might be used within Entitlements::Models::Person to determine
        # the manager for a given person based on the organization chart.
        #
        # person - Reference to Entitlements::Models::Person object calling this method
        #
        # Returns a String with the distinguished name of the person's manager.
        Contract Entitlements::Models::Person => String
        def self.manager(person)
          # User to manager map is assumed to be stored in a YAML file wherein the key is the
          # username and the value is a hash. The value contains a key "manager" with the username
          # of the manager.
          @user_to_manager_map ||= begin
            unless config["manager_map_file"]
              raise ArgumentError, "To use #{self}, `manager_map_file` must be defined in the configuration!"
            end

            manager_map_file = Entitlements::Util::Util.absolute_path(config["manager_map_file"])

            unless File.file?(manager_map_file)
              raise Errno::ENOENT, "The `manager_map_file` #{manager_map_file} does not exist!"
            end

            YAML.load(File.read(manager_map_file), permitted_classes: [Date])
          end

          u = person.uid.downcase
          unless @user_to_manager_map.key?(u)
            raise "User #{u} is not included in manager map data!"
          end
          unless @user_to_manager_map[u]["manager"]
            raise "User #{u} does not have a manager listed in manager map data!"
          end
          @user_to_manager_map[u]["manager"]
        end

        def self.reset!
          @user_to_manager_map = nil
          @extra_config = nil
        end
      end
    end
  end
end
