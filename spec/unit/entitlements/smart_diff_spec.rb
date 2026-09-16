# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "timeout"

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

  it "limits comparison to affected groups" do
    result, = described_class.compare(
      base: base,
      head: head,
      affected_groups: ["teams/same"]
    )
    expect(result["counts"]).to eq("gains" => 0, "losses" => 0)
    expect(result["scope"]).to eq("affected_groups" => ["teams/same"])
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

  it "isolates Ruby state between base and head snapshot processes" do
    Dir.mktmpdir do |base_tree|
      Dir.mktmpdir do |head_tree|
        [base_tree, head_tree].each do |tree|
          FileUtils.cp_r(Dir.glob(File.join(fixture("smart-diff"), "*")), tree)
        end

        File.write(File.join(base_tree, "groups", "teams", "ruby-group.rb"), <<~RUBY)
          Object.const_set(:SmartDiffProcessLeak, true)
          module Entitlements
            class Rule
              class Teams
                class RubyGroup < Entitlements::Rule::Base
                  def members
                    Set.new([Entitlements.cache[:people_obj].read("ALICE")])
                  end
                end
              end
            end
          end
        RUBY
        File.write(File.join(head_tree, "groups", "teams", "ruby-group.rb"), <<~RUBY)
          module Entitlements
            class Rule
              class Teams
                class RubyGroup < Entitlements::Rule::Base
                  def members
                    username = defined?(::SmartDiffProcessLeak) ? "BOB" : "ALICE"
                    Set.new([Entitlements.cache[:people_obj].read(username)])
                  end
                end
              end
            end
          end
        RUBY

        result, = described_class.run(
          base_config: File.join(base_tree, "config.yaml"),
          head_config: File.join(head_tree, "config.yaml"),
          base_sha: "a" * 40,
          head_sha: "b" * 40,
          people_source: fixture("smart-diff/people.yaml"),
          evaluated_at: "2026-09-02T19:58:54Z",
          base_tree: base_tree,
          head_tree: head_tree
        )

        expect(result["scope"]).to eq("affected_groups" => ["teams/ruby-group", "teams_mirror/ruby-group"])
        expect(result["counts"]).to eq("gains" => 0, "losses" => 0)
      end
    end
  end

  it "calculates base and head snapshots in parallel" do
    mutex = Mutex.new
    ready = ConditionVariable.new
    started = 0
    release = false
    allow(described_class).to receive(:snapshot) do |options|
      label = options.fetch(:label)
      mutex.synchronize do
        started += 1
        ready.broadcast
        ready.wait(mutex) until release
      end
      {"label" => label}
    end

    result = nil
    begin
      result = Timeout.timeout(2) do
        thread = Thread.new do
          described_class.send(:parallel_snapshots, "base" => {}, "head" => {})
        end
        mutex.synchronize do
          ready.wait(mutex) until started == 2
          release = true
          ready.broadcast
        end
        thread.value
      end
    ensure
      mutex.synchronize do
        release = true
        ready.broadcast
      end
    end

    expect(result).to eq(
      "base" => {"label" => "base"},
      "head" => {"label" => "head"}
    )
  end

  it "reports snapshot worker failures" do
    status = instance_double(Process::Status, success?: false, exitstatus: 1)
    allow(Open3).to receive(:capture3).and_return(["", "worker error\n", status])

    expect do
      described_class.send(:parallel_snapshots, "base" => {source_sha: "a" * 40})
    end.to raise_error(ArgumentError, "base snapshot failed: worker error")
  end

  it "rejects invalid snapshot worker requirements" do
    expect do
      described_class.send(:snapshot, label: "base", required_features: [nil])
    end.to raise_error(ArgumentError, /required_features/)
  end

  it "rejects invalid snapshot worker output" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(["not json", "", status])

    expect do
      described_class.send(:snapshot, label: "head", source_sha: "b" * 40)
    end.to raise_error(ArgumentError, /head snapshot returned invalid JSON/)
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
