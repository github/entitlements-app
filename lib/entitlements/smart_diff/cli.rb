# frozen_string_literal: true

require "optparse"

module Entitlements
  class SmartDiff
    class Cli
      # :nocov:
      DEFAULT_CONFIG = "config/entitlements.yaml"

      def self.run(argv = ARGV)
        options = parse(argv)
        result, markdown = Entitlements::SmartDiff.run(
          base_config: config_path(options.fetch(:base_tree), options[:base_config]),
          head_config: config_path(options.fetch(:head_tree), options[:head_config]),
          base_sha: options.fetch(:base_sha),
          head_sha: options.fetch(:head_sha),
          people_source: options.fetch(:people_snapshot),
          evaluated_at: options.fetch(:evaluated_at),
          base_tree: options.fetch(:base_tree),
          head_tree: options.fetch(:head_tree),
          markdown_limit: options.fetch(:markdown_limit)
        )
        File.write(options.fetch(:json), Entitlements::SmartDiff.json(result))
        File.write(options.fetch(:markdown), markdown)
        0
      rescue KeyError, OptionParser::ParseError, ArgumentError, SystemCallError => e
        warn "entitlements-smart-diff: #{e.message}"
        1
      end

      def self.parse(argv)
        options = {markdown_limit: Entitlements::SmartDiff::DEFAULT_MARKDOWN_LIMIT}
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: entitlements-smart-diff [options]"
          opts.on("--base-tree PATH") { |value| options[:base_tree] = value }
          opts.on("--head-tree PATH") { |value| options[:head_tree] = value }
          opts.on("--base-config PATH") { |value| options[:base_config] = value }
          opts.on("--head-config PATH") { |value| options[:head_config] = value }
          opts.on("--base-sha SHA") { |value| options[:base_sha] = value }
          opts.on("--head-sha SHA") { |value| options[:head_sha] = value }
          opts.on("--people-snapshot PATH") { |value| options[:people_snapshot] = value }
          opts.on("--evaluated-at TIMESTAMP") { |value| options[:evaluated_at] = value }
          opts.on("--json PATH") { |value| options[:json] = value }
          opts.on("--markdown PATH") { |value| options[:markdown] = value }
          opts.on("--markdown-limit COUNT", Integer) { |value| options[:markdown_limit] = value }
        end
        parser.parse!(argv)
        required = %i[base_tree head_tree base_sha head_sha people_snapshot evaluated_at json markdown]
        missing = required.reject { |key| options.key?(key) }
        raise OptionParser::MissingArgument, missing.join(", ") if missing.any?
        options
      end
      private_class_method :parse

      def self.config_path(tree, configured_path)
        path = configured_path || DEFAULT_CONFIG
        return path if path.start_with?("/")
        File.expand_path(path, tree)
      end
      private_class_method :config_path
      # :nocov:
    end
  end
end
