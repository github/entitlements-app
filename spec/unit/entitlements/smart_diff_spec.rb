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
        {"backend" => "dummy", "entitlement_group" => "teams/new|group", "username" => "<alice>"},
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
    expect(markdown).to include("teams/new\\|group")
    expect(markdown).to include(described_class::LIMITATION)
    expect(described_class.json(result)).to end_with("\n")
  end

  it "renders empty sections and deterministic truncation" do
    unchanged = base.merge("source_sha" => "c" * 40)
    result, markdown = described_class.compare(base: base, head: unchanged, markdown_limit: 1)
    expect(result["counts"]).to eq("gains" => 0, "losses" => 0)
    expect(markdown).to include("0 memberships added; 0 memberships removed")
    expect(markdown.scan("None.").length).to eq(2)

    large_head = head.merge("memberships" => head["memberships"] + [
      {"backend" => "dummy", "entitlement_group" => "teams/new2", "username" => "carol"}
    ])
    _large_result, truncated = described_class.compare(base: base, head: large_head, markdown_limit: 1)
    expect(truncated).to include("1 additional added memberships omitted")
  end

  it "warns without failing when either snapshot is incomplete" do
    incomplete_head = head.merge(
      "complete" => false,
      "warnings" => [{"entitlement_group" => "teams/dynamic", "message" => "uses a live GitHub service"}]
    )
    result, markdown = described_class.compare(base: base, head: incomplete_head)
    expect(result["complete"]).to be false
    expect(result["warnings"]["head"]).to eq(incomplete_head["warnings"])
    expect(markdown).to include("[!WARNING]")
    expect(markdown).to include("1 group skipped")
    expect(markdown).to include("teams/dynamic")
  end

  it "does not report changes for groups incomplete in either snapshot" do
    incomplete_head = head.merge(
      "complete" => false,
      "memberships" => [head["memberships"].last],
      "warnings" => [{"entitlement_group" => "teams/old", "message" => "dynamic"}]
    )
    result, _markdown = described_class.compare(base: base, head: incomplete_head)
    expect(result["losses"]).to be_empty
  end

  it "bounds incomplete warning rows" do
    warnings = 3.times.map do |index|
      {"entitlement_group" => "teams/dynamic-#{index}", "message" => "dynamic"}
    end
    incomplete_head = head.merge("complete" => false, "warnings" => warnings)
    _result, markdown = described_class.compare(base: base, head: incomplete_head, markdown_limit: 1)
    expect(markdown.scan("| head |").length).to eq(0)
    expect(markdown).to include("3 additional incomplete-group warnings omitted")
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
    expect(result["base"]["people_snapshot_sha256"]).to eq(result["head"]["people_snapshot_sha256"])
    expect(result["base"]["evaluated_at"]).to eq(result["head"]["evaluated_at"])
  end

  it "rejects incomplete or inconsistent snapshots" do
    expect { described_class.compare(base: [], head: head) }.to raise_error(ArgumentError, /must be a hash/)
    expect { described_class.compare(base: base.merge("schema_version" => 2), head: head) }.to raise_error(ArgumentError, /schema version/)
    expect { described_class.compare(base: base.reject { |key| key == "source_sha" }, head: head) }.to raise_error(ArgumentError, /missing source_sha/)
    expect { described_class.compare(base: base.merge("memberships" => {}), head: head) }.to raise_error(ArgumentError, /must be an array/)
    expect { described_class.compare(base: base, head: head.merge("people_snapshot_sha256" => "other")) }.to raise_error(ArgumentError, /people snapshots/)
    expect { described_class.compare(base: base, head: head.merge("evaluated_at" => "other")) }.to raise_error(ArgumentError, /evaluation timestamps/)
    expect { described_class.compare(base: base, head: head, markdown_limit: 0) }.to raise_error(ArgumentError, /markdown_limit/)
    expect { described_class.compare(base: base.merge("memberships" => ["bad"]), head: head) }.to raise_error(ArgumentError, /Invalid membership/)
  end
end
