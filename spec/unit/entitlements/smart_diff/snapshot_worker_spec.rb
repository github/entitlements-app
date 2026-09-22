# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../../lib/entitlements/smart_diff/snapshot_worker"

describe Entitlements::SmartDiff::SnapshotWorker do
  it "writes a desired membership snapshot" do
    snapshot = {
      "schema_version" => 1,
      "source_sha" => "a" * 40,
      "people_snapshot_sha256" => "people",
      "evaluated_at" => "2026-09-02T19:58:54Z",
      "people" => {},
      "memberships" => []
    }
    input = StringIO.new(JSON.generate(
      config_file: "/base/config.yaml",
      source_sha: "a" * 40,
      people_source: "/people.yaml",
      evaluated_at: "2026-09-02T19:58:54Z",
      tree_root: "/base",
      entitlement_groups: ["teams/direct"]
    ))
    output = StringIO.new
    error = StringIO.new
    expect(Entitlements::DesiredGroups).to receive(:export).with(
      config_file: "/base/config.yaml",
      source_sha: "a" * 40,
      people_source: "/people.yaml",
      evaluated_at: "2026-09-02T19:58:54Z",
      tree_root: "/base",
      entitlement_groups: ["teams/direct"]
    ).and_return(snapshot)

    expect(described_class.run(input: input, output: output, error: error)).to eq(0), error.string
    expect(error.string).to be_empty
    expect(JSON.parse(output.string)).to eq(snapshot)
  end

  it "reports invalid requests without emitting a snapshot" do
    output = StringIO.new
    error = StringIO.new

    expect(described_class.run(input: StringIO.new("{}"), output: output, error: error)).to eq(1)
    expect(output.string).to be_empty
    expect(error.string).to include("KeyError")
  end
end
