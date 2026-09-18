# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"

describe Entitlements::DesiredGroups do
  let(:config_file) { fixture("smart-diff/config.yaml") }
  let(:people_source) { fixture("smart-diff/people.yaml") }
  let(:source_sha) { "a" * 40 }
  let(:evaluated_at) { "2026-09-02T19:58:54Z" }
  let(:args) do
    {
      config_file: config_file,
      source_sha: source_sha,
      people_source: people_source,
      evaluated_at: evaluated_at
    }
  end

  before do
    allow(Entitlements).to receive(:cache).and_call_original
  end

  it "exports deterministic, normalized desired memberships without provider access" do
    expect(Entitlements::Backend::Dummy::Controller).not_to receive(:new)

    first = described_class.export(**args)
    second = described_class.export(**args)

    expect(first).to eq(second)
    expect(first["schema_version"]).to eq(1)
    expect(first["source_sha"]).to eq(source_sha)
    expect(first["people_snapshot_sha256"]).to eq(Digest::SHA256.file(people_source).hexdigest)
    expect(first["evaluated_at"]).to eq(evaluated_at)
    expect(first["people"]).to eq(
      "Alice" => {"manager" => "Alice"},
      "bob" => {"manager" => "Alice"},
      "contractor" => {"manager" => "Alice"}
    )
    expect(first).not_to have_key("complete")
    expect(first).not_to have_key("warnings")
    expect(first["memberships"]).to eq(first["memberships"].sort_by(&:values))
    expect(first["memberships"].length).to eq(10)
    expect(first["memberships"]).to include(
      {"backend" => "dummy", "entitlement_group" => "teams/direct", "username" => "alice"},
      {"backend" => "dummy", "entitlement_group" => "teams/nested", "username" => "bob"},
      {"backend" => "dummy", "entitlement_group" => "teams/ruby-group", "username" => "alice"},
      {"backend" => "dummy", "entitlement_group" => "teams_mirror/direct", "username" => "alice"}
    )
    expect(first["memberships"]).not_to include(
      {"backend" => "dummy", "entitlement_group" => "teams/expiring", "username" => "alice"},
      {"backend" => "dummy", "entitlement_group" => "teams/filtered", "username" => "contractor"}
    )
  end

  it "serializes byte-for-byte deterministic JSON" do
    expect(described_class.export_json(**args)).to eq(described_class.export_json(**args))
    expect(described_class.export_json(**args)).to end_with("\n")
  end

  it "accepts a Time evaluation value" do
    result = described_class.export(**args.merge(evaluated_at: Time.new(2026, 9, 1, 12, 0, 0, "-04:00")))
    expect(result["evaluated_at"]).to eq("2026-09-01T16:00:00Z")
    expect(result["memberships"]).to include(
      {"backend" => "dummy", "entitlement_group" => "teams/expiring", "username" => "alice"}
    )
  end

  it "sets and restores the source tree environment for configuration ERB" do
    original = ENV["DIR"]
    result = described_class.export(**args.merge(tree_root: fixture("smart-diff")))
    expect(result["memberships"]).not_to be_empty
    expect(ENV["DIR"]).to eq(original)
  end

  it "rejects invalid inputs" do
    expect { described_class.export(**args.merge(config_file: "missing")) }.to raise_error(ArgumentError, /config_file/)
    expect { described_class.export(**args.merge(people_source: "missing")) }.to raise_error(ArgumentError, /people_source/)
    expect { described_class.export(**args.merge(source_sha: "nope")) }.to raise_error(ArgumentError, /source_sha/)
    expect { described_class.export(**args.merge(evaluated_at: "2026-09-02")) }.to raise_error(ArgumentError, /evaluated_at/)
  end

  it "normalizes exported identity facts and rejects malformed people data" do
    Dir.mktmpdir do |directory|
      normalized = File.join(directory, "normalized.yaml")
      File.write(normalized, YAML.dump(
        "alice" => {
          "status" => ["employee"]
        }
      ))
      result = described_class.export(**args.merge(people_source: normalized))
      expect(result.fetch("people")).to eq(
        "alice" => {
          "status" => ["employee"]
        }
      )

      invalid_root = File.join(directory, "invalid-root.yaml")
      File.write(invalid_root, YAML.dump([]))
      expect do
        described_class.send(:people_snapshot, invalid_root)
      end.to raise_error(ArgumentError, /must contain a hash/)

      invalid_attributes = File.join(directory, "invalid-attributes.yaml")
      File.write(invalid_attributes, YAML.dump("alice" => []))
      expect do
        described_class.send(:people_snapshot, invalid_attributes)
      end.to raise_error(ArgumentError, /People attributes for alice must be a hash/)
    end
  end

  it "rejects groups without stable backend identifiers" do
    allow(Entitlements).to receive(:config).and_return("groups" => {"teams" => {}})
    expect { described_class.export(**args) }.to raise_error(ArgumentError, /stable backend identifier/)
  end

  it "can export only requested groups and evaluates Ruby dependencies normally" do
    dynamic_args = args.merge(config_file: fixture("dynamic-groups/config.yaml"))
    result = described_class.export(
      **dynamic_args,
      entitlement_groups: ["teams/static", "teams_mirror/static"]
    )
    expect(result["memberships"]).to eq([
      {"backend" => "dummy", "entitlement_group" => "teams/static", "username" => "alice"},
      {"backend" => "dummy", "entitlement_group" => "teams_mirror/static", "username" => "alice"}
    ])

    expect do
      described_class.export(**dynamic_args, entitlement_groups: ["teams/dynamic"])
    end.to raise_error(KeyError, /DYNAMIC_GROUP_TOKEN/)
  end

  it "treats requested groups missing from one tree as empty" do
    result = described_class.export(**args, entitlement_groups: ["teams/missing"])
    expect(result["memberships"]).to be_empty
  end

  it "treats requested groups in missing directories as empty" do
    allow(Entitlements::Util::Util).to receive(:path_for_group).and_raise(Errno::ENOENT)
    result = described_class.export(**args, entitlement_groups: ["teams/missing"])
    expect(result["memberships"]).to be_empty
  end

  it "rejects multiple files defining the same requested group" do
    Dir.mktmpdir do |directory|
      FileUtils.cp_r(Dir.glob(File.join(fixture("smart-diff"), "*")), directory)
      File.write(File.join(directory, "groups", "teams", "direct.yaml"), "---\nrules: {username: alice}\n")

      expect do
        described_class.export(
          **args.merge(config_file: File.join(directory, "config.yaml")),
          entitlement_groups: ["teams/direct"]
        )
      end.to raise_error(ArgumentError, /Multiple entitlement files/)
    end
  end

end
