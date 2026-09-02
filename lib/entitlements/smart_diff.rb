# frozen_string_literal: true

require "cgi"
require "json"
require "set"
require_relative "smart_diff/scope"

module Entitlements
  class SmartDiff
    SCHEMA_VERSION = 1
    DEFAULT_MARKDOWN_LIMIT = 200
    LIMITATION = "This compares desired entitlement-group membership. It does not predict provider-specific roles, " \
      "resource mappings, drift, invitations, JIT sessions, or API operations."

    def self.run(base_config:, head_config:, base_sha:, head_sha:, people_source:, evaluated_at:, base_tree: nil, head_tree: nil, markdown_limit: DEFAULT_MARKDOWN_LIMIT)
      affected_groups = if base_tree && head_tree
                          Entitlements::SmartDiff::Scope.affected_groups(
                            base_config: base_config,
                            head_config: head_config,
                            base_tree: base_tree,
                            head_tree: head_tree
                          )
                        end
      common = {people_source: people_source, evaluated_at: evaluated_at}
      base = Entitlements::DesiredGroups.export(
        config_file: base_config,
        source_sha: base_sha,
        tree_root: base_tree,
        allow_incomplete: true,
        **common
      )
      head = Entitlements::DesiredGroups.export(
        config_file: head_config,
        source_sha: head_sha,
        tree_root: head_tree,
        allow_incomplete: true,
        **common
      )
      compare(base: base, head: head, markdown_limit: markdown_limit, affected_groups: affected_groups)
    end

    def self.compare(base:, head:, markdown_limit: DEFAULT_MARKDOWN_LIMIT, affected_groups: nil)
      validate_snapshot!(base, "base")
      validate_snapshot!(head, "head")
      raise ArgumentError, "Base and head used different people snapshots" unless base["people_snapshot_sha256"] == head["people_snapshot_sha256"]
      raise ArgumentError, "Base and head used different evaluation timestamps" unless base["evaluated_at"] == head["evaluated_at"]
      raise ArgumentError, "markdown_limit must be a positive integer" unless markdown_limit.is_a?(Integer) && markdown_limit.positive?

      if affected_groups
        base = scoped_snapshot(base, affected_groups)
        head = scoped_snapshot(head, affected_groups)
      end
      base_memberships = indexed_memberships(base)
      head_memberships = indexed_memberships(head)
      incomplete_groups = Set.new((snapshot_warnings(base) + snapshot_warnings(head)).map { |warning| warning.fetch("entitlement_group") })
      base_memberships.delete_if { |identity, _record| incomplete_groups.include?(identity[1]) }
      head_memberships.delete_if { |identity, _record| incomplete_groups.include?(identity[1]) }
      gains = (head_memberships.keys - base_memberships.keys).sort.map { |identity| head_memberships.fetch(identity) }
      losses = (base_memberships.keys - head_memberships.keys).sort.map { |identity| base_memberships.fetch(identity) }

      result = {
        "schema_version" => SCHEMA_VERSION,
        "complete" => snapshot_complete?(base) && snapshot_complete?(head),
        "base" => snapshot_metadata(base),
        "head" => snapshot_metadata(head),
        "warnings" => {"base" => snapshot_warnings(base), "head" => snapshot_warnings(head)},
        "counts" => {"gains" => gains.length, "losses" => losses.length},
        "gains" => gains,
        "losses" => losses
      }
      result["scope"] = {"affected_groups" => affected_groups} if affected_groups
      [result, markdown(result, limit: markdown_limit)]
    end

    def self.json(result)
      JSON.pretty_generate(result) << "\n"
    end

    def self.markdown(result, limit: DEFAULT_MARKDOWN_LIMIT)
      lines = [
        "## Proposed entitlement membership changes",
      ]
      unless result.fetch("complete")
        warning_count = result.fetch("warnings").values.flatten.map { |warning| warning.fetch("entitlement_group") }.uniq.length
        lines.concat([
          "",
          "> [!WARNING]",
          "> This diff is incomplete. #{membership_count(warning_count).sub('membership', 'group')} skipped because calculation depends on dynamic inputs.",
        ])
      end
      lines.concat([
        "",
        "**#{membership_count(result.fetch('counts').fetch('gains'))} added; " \
          "#{membership_count(result.fetch('counts').fetch('losses'))} removed.**",
        "",
        "Base: `#{escape_inline(result.fetch('base').fetch('source_sha'))}`  ",
        "Head: `#{escape_inline(result.fetch('head').fetch('source_sha'))}`",
        ""
      ])
      if result["scope"]
        lines.concat(["Affected entitlement groups: #{result.fetch('scope').fetch('affected_groups').length}", ""])
      end

      remaining = limit
      [["Added", "gains"], ["Removed", "losses"]].each do |heading, key|
        records = result.fetch(key)
        lines.concat(["### #{heading}", ""])
        if records.empty?
          lines.concat(["None.", ""])
          next
        end

        visible = records.first(remaining)
        lines.concat(["| User | Backend | Entitlement group |", "|---|---|---|"])
        visible.each do |record|
          lines << "| #{escape_table(record.fetch('username'))} | #{escape_table(record.fetch('backend'))} | " \
            "#{escape_table(record.fetch('entitlement_group'))} |"
        end
        lines << ""
        remaining -= visible.length
        omitted = records.length - visible.length
        lines.concat(["_#{omitted} additional #{heading.downcase} memberships omitted; see the JSON artifact._", ""]) if omitted.positive?
      end

      lines.concat(["> #{LIMITATION}", ""])
      unless result.fetch("complete")
        warnings = result.fetch("warnings").flat_map do |tree, entries|
          entries.map { |warning| [tree, warning] }
        end.sort_by { |tree, warning| [tree, warning.fetch("entitlement_group")] }
        visible_warnings = warnings.first(remaining)
        lines.concat(["### Incomplete groups", ""])
        if visible_warnings.any?
          lines.concat(["| Tree | Entitlement group | Reason |", "|---|---|---|"])
          visible_warnings.each do |tree, warning|
            lines << "| #{tree} | #{escape_table(warning.fetch('entitlement_group'))} | #{escape_table(warning.fetch('message'))} |"
          end
          lines << ""
        end
        omitted = warnings.length - visible_warnings.length
        if omitted.positive?
          lines.concat(["_#{omitted} additional incomplete-group warnings omitted; see the JSON artifact._", ""])
        end
      end
      lines.join("\n")
    end

    def self.validate_snapshot!(snapshot, label)
      raise ArgumentError, "#{label} snapshot must be a hash" unless snapshot.is_a?(Hash)
      raise ArgumentError, "#{label} snapshot has an unsupported schema version" unless snapshot["schema_version"] == Entitlements::DesiredGroups::SCHEMA_VERSION
      %w[source_sha people_snapshot_sha256 evaluated_at memberships].each do |key|
        raise ArgumentError, "#{label} snapshot is missing #{key}" unless snapshot.key?(key)
      end
      raise ArgumentError, "#{label} memberships must be an array" unless snapshot["memberships"].is_a?(Array)
    end
    private_class_method :validate_snapshot!

    def self.indexed_memberships(snapshot)
      snapshot.fetch("memberships").to_h do |record|
        unless record.is_a?(Hash) && %w[backend entitlement_group username].all? { |key| record[key].is_a?(String) }
          raise ArgumentError, "Invalid membership record: #{record.inspect}"
        end
        identity = record.values_at("backend", "entitlement_group", "username")
        [identity, record]
      end
    end
    private_class_method :indexed_memberships

    def self.snapshot_metadata(snapshot)
      snapshot.slice("source_sha", "people_snapshot_sha256", "evaluated_at", "complete")
    end
    private_class_method :snapshot_metadata

    def self.scoped_snapshot(snapshot, affected_groups)
      included = affected_groups.to_set
      warnings = snapshot_warnings(snapshot).select { |warning| included.include?(warning.fetch("entitlement_group")) }
      snapshot.merge(
        "complete" => warnings.empty?,
        "warnings" => warnings,
        "memberships" => snapshot.fetch("memberships").select do |record|
          included.include?(record.fetch("entitlement_group"))
        end
      )
    end
    private_class_method :scoped_snapshot

    def self.escape_table(value)
      escaped = value.to_s.gsub(/[\r\n]+/, " ").gsub("\\") { "\\\\" }
      CGI.escapeHTML(escaped).gsub("|") { "\\|" }
    end
    private_class_method :escape_table

    def self.escape_inline(value)
      value.to_s.gsub(/[\r\n]+/, " ").gsub("\\") { "\\\\" }.gsub("`") { "\\`" }
    end
    private_class_method :escape_inline

    def self.membership_count(count)
      "#{count} #{count == 1 ? 'membership' : 'memberships'}"
    end
    private_class_method :membership_count

    def self.snapshot_complete?(snapshot)
      snapshot.fetch("complete", true)
    end
    private_class_method :snapshot_complete?

    def self.snapshot_warnings(snapshot)
      snapshot.fetch("warnings", [])
    end
    private_class_method :snapshot_warnings
  end
end
