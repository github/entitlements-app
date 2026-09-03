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
                            head_tree: head_tree,
                            evaluated_at: evaluated_at
                          )
                        end
      common = {people_source: people_source, evaluated_at: evaluated_at}
      base = Entitlements::DesiredGroups.export(
        config_file: base_config,
        source_sha: base_sha,
        tree_root: base_tree,
        skip_dynamic_groups: true,
        **common
      )
      head = Entitlements::DesiredGroups.export(
        config_file: head_config,
        source_sha: head_sha,
        tree_root: head_tree,
        skip_dynamic_groups: true,
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
      gains = (head_memberships.keys - base_memberships.keys).sort.map { |identity| head_memberships.fetch(identity) }
      losses = (base_memberships.keys - head_memberships.keys).sort.map { |identity| base_memberships.fetch(identity) }

      result = {
        "schema_version" => SCHEMA_VERSION,
        "base" => snapshot_metadata(base),
        "head" => snapshot_metadata(head),
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
        "",
        "**#{membership_count(result.fetch('counts').fetch('gains'))} added; " \
          "#{membership_count(result.fetch('counts').fetch('losses'))} removed.**",
        "",
        "Base: `#{result.fetch('base').fetch('source_sha')}`  ",
        "Head: `#{result.fetch('head').fetch('source_sha')}`",
        ""
      ]
      if result["scope"]
        lines.concat(["Affected entitlement groups: #{result.fetch('scope').fetch('affected_groups').length}", ""])
      end

      changes_by_backend = Hash.new { |hash, backend| hash[backend] = [] }
      [["Added", "gains"], ["Removed", "losses"]].each do |change, key|
        result.fetch(key).each do |record|
          changes_by_backend[record.fetch("backend")] << [change, record]
        end
      end

      if changes_by_backend.empty?
        lines.concat(["No membership changes.", ""])
      end

      remaining = limit
      changes_by_backend.sort.each do |backend, changes|
        added_count = changes.count { |change, _record| change == "Added" }
        removed_count = changes.length - added_count
        lines.concat([
          "<details>",
          "<summary><strong>#{escape_html(backend)}</strong> - #{membership_count(added_count)} added; " \
            "#{membership_count(removed_count)} removed</summary>",
          ""
        ])

        visible = changes.first(remaining)
        if visible.any?
          lines.concat(["| Change | User | Entitlement group |", "|---|---|---|"])
          visible.each do |change, record|
            lines << "| #{change} | #{escape_table(record.fetch('username'))} | " \
              "#{escape_table(record.fetch('entitlement_group'))} |"
          end
          lines << ""
        end

        remaining -= visible.length
        omitted = changes.length - visible.length
        lines.concat(["_#{omitted} additional memberships omitted; see the JSON artifact._", ""]) if omitted.positive?
        lines.concat(["</details>", ""])
      end

      lines.concat(["> #{LIMITATION}", ""])
      lines.join("\n")
    end

    def self.validate_snapshot!(snapshot, label)
      raise ArgumentError, "#{label} snapshot must be a hash" unless snapshot.is_a?(Hash)
      raise ArgumentError, "#{label} snapshot has an unsupported schema version" unless snapshot["schema_version"] == Entitlements::DesiredGroups::SCHEMA_VERSION
      %w[source_sha people_snapshot_sha256 evaluated_at memberships].each do |key|
        raise ArgumentError, "#{label} snapshot is missing #{key}" unless snapshot.key?(key)
      end
      unless snapshot.fetch("source_sha").is_a?(String) && snapshot.fetch("source_sha").match?(/\A[0-9a-f]{7,64}\z/i)
        raise ArgumentError, "#{label} snapshot has an invalid source_sha"
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
      snapshot.slice("source_sha", "people_snapshot_sha256", "evaluated_at")
    end
    private_class_method :snapshot_metadata

    def self.scoped_snapshot(snapshot, affected_groups)
      included = affected_groups.to_set
      snapshot.merge(
        "memberships" => snapshot.fetch("memberships").select do |record|
          included.include?(record.fetch("entitlement_group"))
        end
      )
    end
    private_class_method :scoped_snapshot

    def self.escape_html(value)
      CGI.escapeHTML(value.to_s.gsub(/[\r\n]+/, " "))
    end
    private_class_method :escape_html

    def self.escape_table(value)
      escape_html(value).gsub("|") { "&#124;" }
    end
    private_class_method :escape_table

    def self.membership_count(count)
      "#{count} #{count == 1 ? 'membership' : 'memberships'}"
    end
    private_class_method :membership_count
  end
end
