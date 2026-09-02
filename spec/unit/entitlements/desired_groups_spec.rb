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
    expect(first["complete"]).to be true
    expect(first["warnings"]).to eq([])
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

  it "rejects groups without stable backend identifiers" do
    allow(Entitlements).to receive(:config).and_return("groups" => {"teams" => {}})
    expect { described_class.export(**args) }.to raise_error(ArgumentError, /stable backend identifier/)
  end

  it "can skip dynamic groups and report an incomplete snapshot" do
    dynamic_args = args.merge(config_file: fixture("dynamic-groups/config.yaml"))
    expect { described_class.export(**dynamic_args) }
      .to raise_error(KeyError, /DYNAMIC_GROUP_TOKEN/)

    result = described_class.export(**dynamic_args.merge(allow_incomplete: true))
    expect(result["complete"]).to be false
    expect(result["warnings"]).to eq([
      {
        "entitlement_group" => "teams/dynamic",
        "message" => "Dynamic group teams/dynamic uses arbitrary Ruby code and environment variables and network client and live GitHub service"
      },
      {
        "entitlement_group" => "teams/dependent",
        "message" => "Dynamic group teams/dynamic uses arbitrary Ruby code and environment variables and network client and live GitHub service"
      },
      {
        "entitlement_group" => "teams/static-ruby",
        "message" => "Dynamic group teams/static-ruby uses arbitrary Ruby code"
      },
      {
        "entitlement_group" => "teams_mirror/dynamic",
        "message" => "Dynamic group teams/dynamic uses arbitrary Ruby code and environment variables and network client and live GitHub service"
      },
      {
        "entitlement_group" => "teams_mirror/dependent",
        "message" => "Dynamic group teams/dynamic uses arbitrary Ruby code and environment variables and network client and live GitHub service"
      },
      {
        "entitlement_group" => "teams_mirror/static-ruby",
        "message" => "Dynamic group teams/static-ruby uses arbitrary Ruby code"
      }
    ].sort_by { |warning| warning["entitlement_group"] })
    expect(result["memberships"]).to eq([
      {"backend" => "dummy", "entitlement_group" => "teams/static", "username" => "alice"},
      {"backend" => "dummy", "entitlement_group" => "teams_mirror/static", "username" => "alice"}
    ])
  end

  it "does not leak Ruby rule class state between trees" do
    Dir.mktmpdir do |directory|
      FileUtils.cp_r(Dir.glob(File.join(fixture("smart-diff"), "*")), directory)
      ruby_file = File.join(directory, "groups", "teams", "ruby-group.rb")
      File.write(ruby_file, <<~RUBY)
        module Entitlements
          class Rule
            class Teams
              class RubyGroup < Entitlements::Rule::Base
                filter "contractors" => :all
                def members
                  Set.new([Entitlements.cache[:people_obj].read("contractor")])
                end
              end
            end
          end
        end
      RUBY
      base = described_class.export(**args.merge(config_file: File.join(directory, "config.yaml")))
      expect(base["memberships"]).to include(
        {"backend" => "dummy", "entitlement_group" => "teams/ruby-group", "username" => "contractor"}
      )

      File.write(ruby_file, <<~RUBY)
        module Entitlements
          class Rule
            class Teams
              class RubyGroup < Entitlements::Rule::Base
                def members
                  Set.new([Entitlements.cache[:people_obj].read("contractor")])
                end
              end
            end
          end
        end
      RUBY
      head = described_class.export(**args.merge(config_file: File.join(directory, "config.yaml")))
      expect(head["memberships"]).not_to include(
        {"backend" => "dummy", "entitlement_group" => "teams/ruby-group", "username" => "contractor"}
      )
    end
  end
end
