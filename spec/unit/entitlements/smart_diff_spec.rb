# frozen_string_literal: true

require_relative "../spec_helper"

describe Entitlements::SmartDiff do
  let(:base) do
    {
      "schema_version" => 1,
      "source_sha" => "a" * 40,
      "people_snapshot_sha256" => "people",
      "evaluated_at" => "2026-09-02T19:58:54Z",
      "memberships" => [
        {"backend" => "dummy", "entitlement_group" => "teams/old", "username" => "alice"},
        {"backend" => "dummy", "entitlement_group" => "teams/same", "username" => "bob"}
      ]
    }
  end
  let(:head) do
    {
      "schema_version" => 1,
      "source_sha" => "b" * 40,
      "people_snapshot_sha256" => "people",
      "evaluated_at" => "2026-09-02T19:58:54Z",
      "memberships" => [
        {"backend" => "dummy", "entitlement_group" => "teams/new\\|group", "username" => "<alice>"},
        {"backend" => "dummy", "entitlement_group" => "teams/same", "username" => "bob"}
      ]
    }
  end

  it "calculates gains and losses and renders safe bounded Markdown" do
    result, markdown = described_class.compare(base: base, head: head)

    expect(result["counts"]).to eq("gains" => 1, "losses" => 1)
    expect(result["gains"]).to eq([head["memberships"].first])
    expect(result["losses"]).to eq([base["memberships"].first])
    expect(result["base"]).not_to have_key("memberships")
    expect(markdown).to include("1 membership added; 1 membership removed")
    expect(markdown).to include("&lt;alice&gt;")
    expect(markdown).to include("teams/new\\&#124;group")
    expect(markdown).to include("<details>")
    expect(markdown).to include("<summary><strong>dummy</strong>")
    expect(markdown).to include("| Change | User | Entitlement group |")
    expect(markdown).not_to include("| User | Backend |")
    expect(markdown).to include(described_class::LIMITATION)
    expect(described_class.json(result)).to end_with("\n")
  end

  it "renders empty output and deterministic truncation" do
    unchanged = base.merge("source_sha" => "c" * 40)
    result, markdown = described_class.compare(base: base, head: unchanged, markdown_limit: 1)
    expect(result["counts"]).to eq("gains" => 0, "losses" => 0)
    expect(markdown).to include("0 memberships added; 0 memberships removed")
    expect(markdown).to include("No membership changes.")

    large_head = head.merge("memberships" => head["memberships"] + [
      {"backend" => "dummy", "entitlement_group" => "teams/new2", "username" => "carol"}
    ])
    _large_result, truncated = described_class.compare(base: base, head: large_head, markdown_limit: 1)
    expect(truncated).to include("2 additional memberships omitted")
  end

  it "renders one collapsible table per backend" do
    multi_backend_head = head.merge("memberships" => head.fetch("memberships") + [
      {"backend" => "github", "entitlement_group" => "org/team", "username" => "carol"}
    ])
    _result, markdown = described_class.compare(base: base, head: multi_backend_head)
    expect(markdown.scan("<details>").length).to eq(2)
    expect(markdown).to include("<summary><strong>dummy</strong>")
    expect(markdown).to include("<summary><strong>github</strong>")
    expect(markdown).to include("| Added | carol | org/team |")
  end

  it "runs both exports with identical frozen inputs" do
    common = {
      config_file: fixture("smart-diff/config.yaml"),
      people_source: fixture("smart-diff/people.yaml"),
      evaluated_at: "2026-09-02T19:58:54Z"
    }
    result, _markdown = described_class.run(
      base_config: common[:config_file],
      head_config: common[:config_file],
      base_sha: "a" * 40,
      head_sha: "b" * 40,
      people_source: common[:people_source],
      evaluated_at: common[:evaluated_at],
      base_tree: fixture("smart-diff"),
      head_tree: fixture("smart-diff")
    )
    expect(result["counts"]).to eq("gains" => 0, "losses" => 0)
    expect(result).not_to have_key("complete")
    expect(result).not_to have_key("warnings")
    expect(result["scope"]).to eq("affected_groups" => [])
    expect(result["base"]["people_snapshot_sha256"]).to eq(result["head"]["people_snapshot_sha256"])
    expect(result["base"]["evaluated_at"]).to eq(result["head"]["evaluated_at"])

    unscoped, = described_class.run(
      base_config: common[:config_file],
      head_config: common[:config_file],
      base_sha: "a" * 40,
      head_sha: "b" * 40,
      people_source: common[:people_source],
      evaluated_at: common[:evaluated_at]
    )
    expect(unscoped).not_to have_key("scope")
  end

  it "rejects invalid or inconsistent snapshots" do
    expect { described_class.compare(base: [], head: head) }.to raise_error(ArgumentError, /must be a hash/)
    expect { described_class.compare(base: base.merge("schema_version" => 2), head: head) }.to raise_error(ArgumentError, /schema version/)
    expect { described_class.compare(base: base.reject { |key| key == "source_sha" }, head: head) }.to raise_error(ArgumentError, /missing source_sha/)
    expect { described_class.compare(base: base.merge("memberships" => {}), head: head) }.to raise_error(ArgumentError, /must be an array/)
    expect { described_class.compare(base: base, head: head.merge("people_snapshot_sha256" => "other")) }.to raise_error(ArgumentError, /people snapshots/)
    expect { described_class.compare(base: base, head: head.merge("evaluated_at" => "other")) }.to raise_error(ArgumentError, /evaluation timestamps/)
    expect { described_class.compare(base: base, head: head, markdown_limit: 0) }.to raise_error(ArgumentError, /markdown_limit/)
    expect { described_class.compare(base: base.merge("memberships" => ["bad"]), head: head) }.to raise_error(ArgumentError, /Invalid membership/)
    expect { described_class.compare(base: base.merge("source_sha" => "`bad`"), head: head) }.to raise_error(ArgumentError, /source_sha/)
  end
end
