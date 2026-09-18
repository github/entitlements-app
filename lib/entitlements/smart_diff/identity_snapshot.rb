# frozen_string_literal: true

require "date"
require "digest"
require "tempfile"
require "yaml"

module Entitlements
  class SmartDiff
    class IdentitySnapshot
      SOURCE_PATHS = %w[
        config/workday.yaml
        config/workday-overrides.yaml
      ].freeze
      EXTERNAL_GLOB = "external/*.yaml"

      def self.sources_changed?(base_tree:, head_tree:)
        source_digests(base_tree) != source_digests(head_tree)
      end

      def self.with_file(tree_root)
        snapshot = build(tree_root)
        Tempfile.create(["entitlements-people-", ".yaml"]) do |file|
          file.write(YAML.dump(snapshot.sort.to_h))
          file.flush
          yield file.path
        end
      end

      def self.build(tree_root)
        tree = File.expand_path(tree_root)
        workday = load_hash(File.join(tree, SOURCE_PATHS.first), required: true)
        overrides = load_hash(File.join(tree, SOURCE_PATHS.last), required: false)
        apply_overrides!(workday, overrides)

        Dir.glob(File.join(tree, EXTERNAL_GLOB)).sort.each do |path|
          load_hash(path, required: true).each { |username, attributes| workday[username] ||= attributes }
        end
        workday
      end

      def self.source_digests(tree_root)
        tree = File.expand_path(tree_root)
        paths = SOURCE_PATHS.map { |path| File.join(tree, path) }
        paths.concat(Dir.glob(File.join(tree, EXTERNAL_GLOB)).sort)
        paths.to_h do |path|
          relative = path.delete_prefix("#{tree}/")
          [relative, File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil]
        end
      end
      private_class_method :source_digests

      def self.load_hash(path, required:)
        unless File.file?(path)
          raise ArgumentError, "Identity source #{path} does not exist" if required
          return {}
        end

        data = YAML.safe_load_file(path, permitted_classes: [Date]) || {}
        raise ArgumentError, "Identity source #{path} must contain a hash" unless data.is_a?(Hash)
        data
      end
      private_class_method :load_hash

      def self.apply_overrides!(people, overrides)
        removals = overrides.fetch("removals", [])
        additions = overrides.fetch("additions", {})
        replacements = overrides.fetch("replacements", {})
        renames = overrides.fetch("renames", {})
        raise ArgumentError, "Identity override removals must be an array" unless removals.is_a?(Array)
        [additions, replacements, renames].each do |value|
          raise ArgumentError, "Identity override sections must be hashes" unless value.is_a?(Hash)
        end

        removals.each { |username| people.delete(username) }
        people.merge!(additions)
        replacements.each do |username, attributes|
          next unless people.key?(username)
          raise ArgumentError, "Identity replacement for #{username} must contain a hash" unless attributes.is_a?(Hash)

          people.fetch(username).merge!(attributes)
        end
        renames.each do |old_name, new_name|
          next unless people.key?(old_name)

          people[new_name] = people.delete(old_name)
          people.each_value do |attributes|
            attributes["manager"] = new_name if attributes["manager"] == old_name
          end
        end
        people
      end
      private_class_method :apply_overrides!
    end
  end
end
