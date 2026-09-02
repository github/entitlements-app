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
      head_tree: fixture("smart-diff")
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
        end

        expect(described_class.affected_groups(
          base_config: File.join(base, "config.yaml"),
          head_config: File.join(head, "config.yaml"),
          base_tree: base,
          head_tree: head
        )).to eq([
          "internal/engineers",
          "teams/nested",
          "teams/wildcard",
          "teams_mirror/nested",
          "teams_mirror/wildcard"
        ])
      end
    end
  end
end
