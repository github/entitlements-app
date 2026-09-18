# frozen_string_literal: true

require "digest"
require "json"

module Entitlements
  class DesiredGroups
    SCHEMA_VERSION = 1

    def self.export(config_file:, source_sha:, people_source:, evaluated_at:, tree_root: nil, entitlement_groups: nil)
      validate_inputs!(
        config_file: config_file,
        source_sha: source_sha,
        people_source: people_source,
        evaluated_at: evaluated_at
      )

      evaluation_time = parse_time(evaluated_at)
      people_hash = Digest::SHA256.file(people_source).hexdigest
      original_dir = ENV["DIR"]
      ENV["DIR"] = File.expand_path(tree_root) if tree_root

      Entitlements.reset!
      Entitlements.config_file = config_file
      backend_identifiers = backend_identifiers(Entitlements.config)
      use_people_snapshot!(people_source)
      Entitlements.validate_configuration_file!
      Entitlements.evaluation_time = evaluation_time
      Entitlements.load_extras if Entitlements.config.key?("extras")
      Entitlements.prefetch_people
      Entitlements.cache[:desired_groups_export] = true
      Entitlements.register_filters if Entitlements.config.key?("filters")

      memberships = export_memberships(backend_identifiers, entitlement_groups: entitlement_groups)
      {
        "schema_version" => SCHEMA_VERSION,
        "source_sha" => source_sha.downcase,
        "people_snapshot_sha256" => people_hash,
        "evaluated_at" => evaluation_time.utc.iso8601,
        "people" => people_snapshot(people_source),
        "memberships" => memberships
      }
    ensure
      Entitlements.reset!
      if tree_root
        original_dir ? ENV["DIR"] = original_dir : ENV.delete("DIR")
      end
    end

    def self.export_json(**args)
      JSON.pretty_generate(export(**args)) << "\n"
    end

    def self.validate_inputs!(config_file:, source_sha:, people_source:, evaluated_at:)
      raise ArgumentError, "config_file must be a readable file" unless File.file?(config_file) && File.readable?(config_file)
      raise ArgumentError, "people_source must be a readable file" unless File.file?(people_source) && File.readable?(people_source)
      raise ArgumentError, "source_sha must be a commit SHA" unless source_sha.is_a?(String) && source_sha.match?(/\A[0-9a-f]{7,64}\z/i)

      parse_time(evaluated_at)
    end
    private_class_method :validate_inputs!

    def self.parse_time(value)
      parsed = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
      raise ArgumentError, "evaluated_at must include a timezone" if !value.is_a?(Time) && value.to_s !~ /(Z|[+-]\d{2}:\d{2})\z/
      parsed
    rescue ArgumentError
      raise ArgumentError, "evaluated_at must be an ISO 8601 timestamp with a timezone"
    end
    private_class_method :parse_time

    def self.backend_identifiers(config)
      config.fetch("groups").to_h do |group_name, group_config|
        identifier = group_config["backend"] || group_config["type"]
        unless identifier.is_a?(String) && !identifier.empty?
          raise ArgumentError, "Group #{group_name.inspect} has no stable backend identifier"
        end
        [group_name, identifier]
      end
    end
    private_class_method :backend_identifiers

    def self.use_people_snapshot!(people_source)
      Entitlements.config["people"] = {
        "smart_diff" => {
          "type" => "yaml",
          "config" => {"filename" => File.expand_path(people_source)}
        }
      }
      Entitlements.config["people_data_source"] = "smart_diff"
    end
    private_class_method :use_people_snapshot!

    def self.people_snapshot(people_source)
      data = YAML.safe_load_file(people_source, permitted_classes: [Date]) || {}
      raise ArgumentError, "people_source must contain a hash" unless data.is_a?(Hash)

      data.to_h do |username, attributes|
        raise ArgumentError, "People attributes for #{username} must be a hash" unless attributes.is_a?(Hash)
        [username.to_s, attributes.transform_keys(&:to_s)]
      end
    end
    private_class_method :people_snapshot

    def self.export_memberships(backend_identifiers, entitlement_groups:)
      return export_all_memberships(backend_identifiers) unless entitlement_groups

      records = {}
      entitlement_groups.sort.each do |entitlement_group|
        group_name = configured_group_name(entitlement_group)
        next unless group_name

        username_records(
          backend: backend_identifiers.fetch(group_name),
          entitlement_group: entitlement_group,
          members: members_for(entitlement_group, group_name)
        ).each do |record|
          records[record.values_at("backend", "entitlement_group", "username")] = record
        end
      end
      records.values.sort_by { |record| record.values_at("backend", "entitlement_group", "username") }
    end
    private_class_method :export_memberships

    def self.export_all_memberships(backend_identifiers)
      records = {}
      exportable_groups.each do |group_name, group_config|
        Entitlements::Data::Groups::Calculated.read_all(group_name, group_config).each do |group_dn|
          group = Entitlements::Data::Groups::Calculated.read(group_dn)
          username_records(
            backend: backend_identifiers.fetch(group_name),
            entitlement_group: "#{group_name}/#{group.cn}",
            members: group.members
          ).each do |record|
            records[record.values_at("backend", "entitlement_group", "username")] = record
          end
        end
      end
      records.values.sort_by { |record| record.values_at("backend", "entitlement_group", "username") }
    end
    private_class_method :export_all_memberships

    def self.configured_group_name(entitlement_group)
      Entitlements.config.fetch("groups").keys.select do |group_name|
        entitlement_group.start_with?("#{group_name}/")
      end.max_by(&:length)
    end
    private_class_method :configured_group_name

    def self.members_for(entitlement_group, group_name)
      group_config = Entitlements.config.fetch("groups").fetch(group_name)
      cn = entitlement_group.delete_prefix("#{group_name}/")
      if group_config["mirror"]
        return members_for("#{group_config.fetch('mirror')}/#{cn}", group_config.fetch("mirror"))
      end

      group_path = Entitlements::Util::Util.path_for_group(group_name)
      filenames = %w[rb txt yaml].filter_map do |extension|
        filename = File.join(group_path, "#{cn}.#{extension}")
        filename if File.file?(filename)
      end
      return Set.new if filenames.empty?
      raise ArgumentError, "Multiple entitlement files found for #{entitlement_group}" if filenames.length > 1

      ruleset = Entitlements::Data::Groups::Calculated.ruleset(
        filename: filenames.first,
        config: group_config
      )
      ruleset.modified_filtered_members
    rescue Errno::ENOENT
      Set.new
    end
    private_class_method :members_for

    def self.username_records(backend:, entitlement_group:, members:)
      members.map do |member|
        {
          "backend" => backend,
          "entitlement_group" => entitlement_group,
          "username" => member.uid.downcase
        }
      end
    end
    private_class_method :username_records

    def self.exportable_groups
      Entitlements.config.fetch("groups").select { |_name, config| config.key?("base") }.sort_by do |group_name, config|
        backend = Entitlements.backends.fetch(config.fetch("type"))
        [backend.fetch(:priority), config.key?("mirror") ? 1 : 0, group_name.length, group_name]
      end
    end
    private_class_method :exportable_groups
  end
end
