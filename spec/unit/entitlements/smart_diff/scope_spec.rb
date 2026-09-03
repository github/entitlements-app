# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::SmartDiff::Scope do
  def copy_fixture(destination)
    FileUtils.cp_r(Dir.glob(File.join(fixture("smart-diff"), "*")), destination)
  end

  it "returns no groups when entitlement files are unchanged" do
    expect(described_class.affected_groups(
      base_config: fixture("smart-diff/config.yaml"),
      head_config: fixture("smart-diff/config.yaml"),
      base_tree: fixture("smart-diff"),
      head_tree: fixture("smart-diff"),
      evaluated_at: "2026-09-02T19:58:54Z"
    )).to eq([])
  end

  it "includes changed groups, static dependents, and mirrors" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        copy_fixture(base)
        copy_fixture(head)
        File.open(File.join(head, "groups", "internal", "engineers.txt"), "a") do |file|
          file.puts "username = contractor"
        end
        [base, head].each do |tree|
          File.write(
            File.join(tree, "groups", "teams", "wildcard.txt"),
            "group = internal/*\n"
          )
          File.write(
            File.join(tree, "groups", "teams", "flow.yaml"),
            "---\nrules: {group: internal/engineers}\n"
          )
        end

        expect(described_class.affected_groups(
          base_config: File.join(base, "config.yaml"),
          head_config: File.join(head, "config.yaml"),
          base_tree: base,
          head_tree: head,
          evaluated_at: "2026-09-02T19:58:54Z"
        )).to eq([
          "internal/engineers",
          "teams/flow",
          "teams/nested",
          "teams/wildcard",
          "teams_mirror/flow",
          "teams_mirror/nested",
          "teams_mirror/wildcard"
        ])
      end
    end
  end

  it "includes groups whose configured filters depend on a changed group" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        copy_fixture(base)
        copy_fixture(head)
        File.open(File.join(head, "groups", "internal", "contractors.txt"), "a") do |file|
          file.puts "username = Alice"
        end

        affected = described_class.affected_groups(
          base_config: File.join(base, "config.yaml"),
          head_config: File.join(head, "config.yaml"),
          base_tree: base,
          head_tree: head,
          evaluated_at: "2026-09-02T19:58:54Z"
        )
        expect(affected).to include("internal/contractors", "teams/filtered", "teams_mirror/filtered")
      end
    end
  end

  it "honors filter path inclusions and exclusions" do
    expect(described_class.send(:filter_applies?, "/groups/included/team.txt", {
      "included_paths" => ["included"]
    })).to be true
    expect(described_class.send(:filter_applies?, "/groups/other/team.txt", {
      "included_paths" => ["included"]
    })).to be false
    expect(described_class.send(:filter_applies?, "/groups/excluded/team.txt", {
      "excluded_paths" => ["excluded"]
    })).to be false
    expect(described_class.send(:filter_applies?, "/groups/other/team.txt", {
      "excluded_paths" => ["excluded"]
    })).to be true
  end
end
