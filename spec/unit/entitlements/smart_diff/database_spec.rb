# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"

describe Entitlements::SmartDiff::Database do
  let(:result) do
    {
      "schema_version" => 1,
      "base" => {
        "source_sha" => "a" * 40,
        "people_snapshot_sha256" => "base-people",
        "evaluated_at" => "2026-09-18T14:00:19Z"
      },
      "head" => {
        "source_sha" => "b" * 40,
        "people_snapshot_sha256" => "head-people",
        "evaluated_at" => "2026-09-18T14:00:19Z"
      },
      "counts" => {"gains" => 1, "losses" => 1},
      "gains" => [
        {"backend" => "aad", "entitlement_group" => "apps/admin", "username" => "alice"}
      ],
      "losses" => [
        {"backend" => "ldap", "entitlement_group" => "pizza_teams/old", "username" => "bob"}
      ],
      "people" => {
        "base" => [
          {"username" => "alice", "attributes" => {"country" => "CA"}},
          {"username" => "bob", "attributes" => {"status" => ["employee"]}}
        ],
        "head" => [
          {"username" => "alice", "attributes" => {"country" => "US"}}
        ]
      },
      "scope" => {"affected_groups" => ["apps/admin", "pizza_teams/old"]}
    }
  end

  it "writes the canonical schema, facts, changes, and SQL-backed Markdown" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "smart-diff.sqlite3")
      described_class.write(path: path, result: result)

      described_class.read(path) do |db|
        expect(db.query_single_splat("PRAGMA integrity_check")).to eq("ok")
        expect(db.query_single_splat("SELECT schema_version FROM metadata")).to eq(1)
        expect(db.query_single_splat("SELECT count(*) FROM membership_changes")).to eq(2)
        expect(db.query_single_splat(<<~SQL)).to eq("US")
          SELECT json_extract(head_attributes_json, '$.country')
          FROM change_context
          WHERE username = 'alice'
        SQL
        tables = db.query(<<~SQL).map { |row| row.fetch(:name) }
          SELECT name
          FROM sqlite_schema
          WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        SQL
        expect(tables).to contain_exactly("affected_groups", "membership_changes", "metadata", "people", "snapshots")
      end

      markdown = described_class.markdown(path: path, limit: 1)
      expect(markdown).to include("1 membership added; 1 membership removed")
      expect(markdown).to include("query the SQLite artifact")
      expect(markdown).to include("Base identity: `base-people`")
      expect(markdown).to include("Affected entitlement groups: 2")
    end
  end

  it "preserves an explicitly empty scope" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "smart-diff.sqlite3")
      described_class.write(
        path: path,
        result: result.merge(
          "gains" => [],
          "losses" => [],
          "people" => {"base" => [], "head" => []},
          "scope" => {"affected_groups" => []}
        )
      )

      expect(described_class.markdown(path: path, limit: 10)).to include("Affected entitlement groups: 0")
    end
  end
end
