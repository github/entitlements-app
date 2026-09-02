# frozen_string_literal: true

require "digest"
require "set"

module Entitlements
  class SmartDiff
    class Scope
      GROUP_REFERENCE = /^\s*(?:-\s*)?(?:group|entitlements_group)\s*(?:!=|=|:)\s*["']?([^"'\s#]+)/
      GROUP_FILE_EXTENSIONS = %w[.rb .txt .yaml].freeze

      def self.affected_groups(base_config:, head_config:, base_tree:, head_tree:)
        base = catalog(config_file: base_config, tree: base_tree)
        head = catalog(config_file: head_config, tree: head_tree)
        all_groups = base.fetch(:groups) | head.fetch(:groups)
        changed_groups = changed_groups(base, head)
        reverse_dependencies = reverse_dependencies(base, head, all_groups)

        affected = changed_groups.dup
        pending = changed_groups.to_a
        until pending.empty?
          group = pending.shift
          reverse_dependencies.fetch(group, Set.new).each do |dependent|
            next if affected.include?(dependent)

            affected.add(dependent)
            pending << dependent
          end
        end
        affected.to_a.sort
      end

      def self.catalog(config_file:, tree:)
        original_dir = ENV["DIR"]
        ENV["DIR"] = File.expand_path(tree)
        Entitlements.reset!
        Entitlements.config_file = config_file
        groups_config = Entitlements.config.fetch("groups")
        groups = Set.new
        files = {}
        path_groups = Hash.new { |hash, key| hash[key] = Set.new }
        references = Hash.new { |hash, key| hash[key] = Set.new }
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
            next if File.extname(filename) == ".rb"

            File.foreach(filename) do |line|
              match = GROUP_REFERENCE.match(line)
              references[group_id].add(match[1]) if match
            end
          end
        end

        mirrors.each do |mirror_name, source_name|
          groups.select { |group_id| group_id.start_with?("#{source_name}/") }.each do |source_group|
            mirror_group = "#{mirror_name}/#{source_group.delete_prefix("#{source_name}/")}"
            groups.add(mirror_group)
            references[mirror_group].add(source_group)
          end
        end

        {
          config_digest: Digest::SHA256.file(config_file).hexdigest,
          files: files,
          groups: groups,
          path_groups: path_groups,
          references: references
        }
      ensure
        Entitlements.reset!
        original_dir ? ENV["DIR"] = original_dir : ENV.delete("DIR")
      end
      private_class_method :catalog

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
