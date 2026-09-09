# frozen_string_literal: true

require "digest"
require "set"

module Entitlements
  class SmartDiff
    class Scope
      GROUP_FILE_EXTENSIONS = %w[.rb .txt .yaml].freeze

      def self.affected_groups(base_config:, head_config:, base_tree:, head_tree:, evaluated_at:)
        base = catalog(config_file: base_config, tree: base_tree, evaluated_at: evaluated_at)
        head = catalog(config_file: head_config, tree: head_tree, evaluated_at: evaluated_at)
        all_groups = base.fetch(:groups) | head.fetch(:groups)
        changed_groups = changed_groups(base, head)
        reverse_dependencies = reverse_dependencies(base, head, all_groups)
        dynamic_groups = dependency_closure(
          base.fetch(:dynamic_groups) | head.fetch(:dynamic_groups),
          reverse_dependencies
        )

        (dependency_closure(changed_groups, reverse_dependencies) - dynamic_groups).to_a.sort
      end

      def self.catalog(config_file:, tree:, evaluated_at:)
        original_dir = ENV["DIR"]
        ENV["DIR"] = File.expand_path(tree)
        Entitlements.reset!
        Entitlements.config_file = config_file
        groups_config = Entitlements.config.fetch("groups")
        Entitlements.evaluation_time = Time.iso8601(evaluated_at.to_s)
        Entitlements.load_extras if Entitlements.config.key?("extras")
        Entitlements.register_filters if Entitlements.config.key?("filters")
        groups = Set.new
        files = {}
        path_groups = Hash.new { |hash, key| hash[key] = Set.new }
        references = Hash.new { |hash, key| hash[key] = Set.new }
        dynamic_groups = Set.new
        mirrors = []

        groups_config.each do |group_name, group_config|
          if group_config["mirror"]
            mirrors << [group_name, group_config.fetch("mirror")]
            next
          end

          begin
            group_path = Entitlements::Util::Util.path_for_group(group_name)
          rescue Errno::ENOENT
            next
          end
          Dir.children(group_path).sort.each do |basename|
            filename = File.join(group_path, basename)
            next unless File.file?(filename)
            next unless GROUP_FILE_EXTENSIONS.include?(File.extname(filename))

            group_id = "#{group_name}/#{File.basename(filename, File.extname(filename))}"
            relative_path = relative_path(filename, tree)
            groups.add(group_id)
            path_groups[relative_path].add(group_id)
            files[relative_path] = Digest::SHA256.file(filename).hexdigest
            if File.extname(filename) == ".rb"
              dynamic_groups.add(group_id)
              next
            end

            ruleset = Entitlements::Data::Groups::Calculated.ruleset(
              filename: filename,
              config: group_config
            )
            collect_group_references(ruleset.send(:rules), references[group_id])
            collect_filter_references(ruleset, filename, references[group_id])
          end
        end

        mirrors.each do |mirror_name, source_name|
          groups.select { |group_id| group_id.start_with?("#{source_name}/") }.each do |source_group|
            mirror_group = "#{mirror_name}/#{source_group.delete_prefix("#{source_name}/")}"
            groups.add(mirror_group)
            references[mirror_group].add(source_group)
            dynamic_groups.add(mirror_group) if dynamic_groups.include?(source_group)
          end
        end

        {
          config_digest: Digest::SHA256.file(config_file).hexdigest,
          files: files,
          groups: groups,
          path_groups: path_groups,
          references: references,
          dynamic_groups: dynamic_groups
        }
      ensure
        Entitlements.reset!
        original_dir ? ENV["DIR"] = original_dir : ENV.delete("DIR")
      end
      private_class_method :catalog

      def self.collect_group_references(value, result)
        case value
        when Array
          value.each { |item| collect_group_references(item, result) }
        when Hash
          value.each do |key, item|
            if %w[group entitlements_group].include?(key) && item.is_a?(String)
              result.add(item)
            else
              collect_group_references(item, result)
            end
          end
        end
      end
      private_class_method :collect_group_references

      def self.collect_filter_references(ruleset, filename, result)
        ruleset.filters.each do |filter_name, filter_value|
          next if filter_value == :all

          filter = Entitlements::Data::Groups::Calculated.filters_index.fetch(filter_name)
          next unless filter.fetch(:class) <= Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup
          next unless filter_applies?(filename, filter.fetch(:config))

          result.add(filter.fetch(:config).fetch("group"))
        end
      end
      private_class_method :collect_filter_references

      def self.filter_applies?(filename, config)
        included = config.fetch("included_paths", [])
        excluded = config.fetch("excluded_paths", [])
        return true if included.empty? && excluded.empty?

        excluded_match = excluded.any? { |path| filename.include?(path) }
        included_match = included.any? { |path| filename.include?(path) }
        (!excluded.empty? && !excluded_match) || (!included.empty? && included_match)
      end
      private_class_method :filter_applies?

      def self.changed_groups(base, head)
        return base.fetch(:groups) | head.fetch(:groups) if base.fetch(:config_digest) != head.fetch(:config_digest)

        paths = base.fetch(:files).keys | head.fetch(:files).keys
        paths.each_with_object(Set.new) do |path, result|
          next if base.fetch(:files)[path] == head.fetch(:files)[path]

          result.merge(base.fetch(:path_groups)[path])
          result.merge(head.fetch(:path_groups)[path])
        end
      end
      private_class_method :changed_groups

      def self.dependency_closure(initial_groups, reverse_dependencies)
        result = initial_groups.dup
        pending = initial_groups.to_a
        until pending.empty?
          group = pending.shift
          reverse_dependencies.fetch(group, Set.new).each do |dependent|
            next if result.include?(dependent)

            result.add(dependent)
            pending << dependent
          end
        end
        result
      end
      private_class_method :dependency_closure

      def self.reverse_dependencies(base, head, all_groups)
        result = Hash.new { |hash, key| hash[key] = Set.new }
        references = merge_references(base.fetch(:references), head.fetch(:references))
        references.each do |dependent, group_references|
          group_references.each do |reference|
            matching_groups(reference, all_groups).each { |dependency| result[dependency].add(dependent) }
          end
        end
        result
      end
      private_class_method :reverse_dependencies

      def self.merge_references(base, head)
        (base.keys | head.keys).to_h do |group|
          [group, base.fetch(group, Set.new) | head.fetch(group, Set.new)]
        end
      end
      private_class_method :merge_references

      def self.matching_groups(reference, all_groups)
        return [reference] unless reference.include?("*")

        pattern = Regexp.new("\\A#{Regexp.escape(reference).gsub('\\*', '.*')}\\z")
        all_groups.select { |group| pattern.match?(group) }
      end
      private_class_method :matching_groups

      def self.relative_path(filename, tree)
        filename.delete_prefix("#{File.expand_path(tree)}/")
      end
      private_class_method :relative_path
    end
  end
end
