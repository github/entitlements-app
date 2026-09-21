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

  it "fails for changed entitlement files without a supported extension" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        copy_fixture(base)
        copy_fixture(head)
        File.write(File.join(head, "groups", "teams", "no-extension"), "username = Alice\n")

        expect do
          described_class.affected_groups(
            base_config: File.join(base, "config.yaml"),
            head_config: File.join(head, "config.yaml"),
            base_tree: base,
            head_tree: head,
            evaluated_at: "2026-09-02T19:58:54Z"
          )
        end.to raise_error(ArgumentError, /groups\/teams\/no-extension has no extension/)

        FileUtils.rm(File.join(head, "groups", "teams", "no-extension"))
        File.write(File.join(head, "groups", "teams", "unsupported.json"), "{}")
        expect do
          described_class.affected_groups(
            base_config: File.join(base, "config.yaml"),
            head_config: File.join(head, "config.yaml"),
            base_tree: base,
            head_tree: head,
            evaluated_at: "2026-09-02T19:58:54Z"
          )
        end.to raise_error(ArgumentError, /groups\/teams\/unsupported.json has unsupported extension ".json"/)
      end
    end
  end

  it "ignores changes to README.md and PR_TEMPLATE.md within a group directory" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        copy_fixture(base)
        copy_fixture(head)
        %w[README.md PR_TEMPLATE.md].each do |ignored_file|
          File.write(File.join(base, "groups", "teams", ignored_file), "base copy\n")
          File.write(File.join(head, "groups", "teams", ignored_file), "head copy\n")
        end

        expect(described_class.affected_groups(
          base_config: File.join(base, "config.yaml"),
          head_config: File.join(head, "config.yaml"),
          base_tree: base,
          head_tree: head,
          evaluated_at: "2026-09-02T19:58:54Z"
        )).to eq([])
      end
    end
  end

  it "evaluates every cataloged group when identity sources change" do
    affected = described_class.affected_groups(
      base_config: fixture("smart-diff/config.yaml"),
      head_config: fixture("smart-diff/config.yaml"),
      base_tree: fixture("smart-diff"),
      head_tree: fixture("smart-diff"),
      evaluated_at: "2026-09-02T19:58:54Z",
      identity_sources_changed: true
    )

    expect(affected).to include(
      "internal/engineers",
      "teams/direct",
      "teams/filtered",
      "teams_mirror/direct",
      "teams_mirror/filtered"
    )
  end

  it "globally validates unchanged supported entitlement files" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        copy_fixture(base)
        copy_fixture(head)
        [base, head].each do |tree|
          File.write(File.join(tree, "groups", "teams", "invalid.txt"), "description = Missing rules\n")
        end

        expect do
          described_class.affected_groups(
            base_config: File.join(base, "config.yaml"),
            head_config: File.join(head, "config.yaml"),
            base_tree: base,
            head_tree: head,
            evaluated_at: "2026-09-02T19:58:54Z",
            identity_sources_changed: true
          )
        end.to raise_error(RuntimeError, /No conditions were found in .*invalid.txt/)
      end
    end
  end

  it "keeps inline predicate and contradictory filter validation fail closed" do
    {
      "invalid-predicate.txt" => "username = Alice; expiration 2029-09-10\n",
      "contradictory-filter.txt" => "username = Alice\nfilter_contractors = all\nfilter_contractors = internal/contractors\n"
    }.each do |filename, content|
      Dir.mktmpdir do |base|
        Dir.mktmpdir do |head|
          copy_fixture(base)
          copy_fixture(head)
          [base, head].each do |tree|
            File.write(File.join(tree, "groups", "teams", filename), content)
          end

          expect do
            described_class.affected_groups(
              base_config: File.join(base, "config.yaml"),
              head_config: File.join(head, "config.yaml"),
              base_tree: base,
              head_tree: head,
              evaluated_at: "2026-09-02T19:58:54Z",
              identity_sources_changed: true
            )
          end.to raise_error(/#{Regexp.escape(filename)}/)
        end
      end
    end
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

  it "includes changed dynamic groups and all groups that depend on them" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        [base, head].each do |tree|
          FileUtils.cp_r(Dir.glob(File.join(fixture("dynamic-groups"), "*")), tree)
        end
        File.open(File.join(head, "groups", "teams", "dynamic.rb"), "a") do |file|
          file.puts "# changed"
        end

        expect(described_class.affected_groups(
          base_config: File.join(base, "config.yaml"),
          head_config: File.join(head, "config.yaml"),
          base_tree: base,
          head_tree: head,
          evaluated_at: "2026-09-02T19:58:54Z"
        )).to eq([
          "teams/dependent",
          "teams/dynamic",
          "teams/filtered",
          "teams_mirror/dependent",
          "teams_mirror/dynamic",
          "teams_mirror/filtered"
        ])
      end
    end
  end

  it "includes groups referenced by per-file filter values" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        copy_fixture(base)
        copy_fixture(head)
        [base, head].each do |tree|
          File.write(
            File.join(tree, "groups", "teams", "filter-target.txt"),
            "username = contractor\n"
          )
          File.write(
            File.join(tree, "groups", "teams", "filter-dependent.txt"),
            "username = contractor\nfilter_contractors = teams/filter-target\n"
          )
        end
        File.open(File.join(head, "groups", "teams", "filter-target.txt"), "a") do |file|
          file.puts "username = alice"
        end

        expect(described_class.affected_groups(
          base_config: File.join(base, "config.yaml"),
          head_config: File.join(head, "config.yaml"),
          base_tree: base,
          head_tree: head,
          evaluated_at: "2026-09-02T19:58:54Z"
        )).to include("teams/filter-dependent")
      end
    end
  end
end
