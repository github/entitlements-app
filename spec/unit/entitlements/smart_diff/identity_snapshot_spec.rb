# frozen_string_literal: true

require_relative "../../spec_helper"
require "fileutils"
require "tmpdir"

describe Entitlements::SmartDiff::IdentitySnapshot do
  def write_yaml(root, relative_path, value)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(value))
  end

  it "uses canonical additions, removals, replacements, renames, and external precedence" do
    Dir.mktmpdir do |tree|
      write_yaml(tree, "config/workday.yaml", {
        "alice" => {"manager" => "old", "status" => ["employee"]},
        "bob" => {"manager" => "alice"},
        "removed" => {"manager" => "alice"}
      })
      write_yaml(tree, "config/workday-overrides.yaml", {
        "additions" => {"added" => {"manager" => "alice"}},
        "removals" => ["removed"],
        "replacements" => {"alice" => {"status" => ["contractor"]}, "missing" => {"manager" => "nobody"}},
        "renames" => {"alice" => "alice-renamed"}
      })
      write_yaml(tree, "external/users.yaml", {
        "bob" => {"manager" => "external"},
        "external" => {"manager" => "alice-renamed"}
      })

      expect(described_class.build(tree)).to eq(
        "added" => {"manager" => "alice-renamed"},
        "alice-renamed" => {"manager" => "old", "status" => ["contractor"]},
        "bob" => {"manager" => "alice-renamed"},
        "external" => {"manager" => "alice-renamed"}
      )
    end
  end

  it "detects identity source changes and writes a deterministic snapshot file" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |head|
        [base, head].each do |tree|
          write_yaml(tree, "config/workday.yaml", {"alice" => {"manager" => "alice"}})
        end
        write_yaml(base, "config/workday-overrides.yaml", {})
        write_yaml(head, "config/workday-overrides.yaml", {"removals" => ["alice"]})

        expect(described_class.sources_changed?(base_tree: base, head_tree: head)).to be true
        described_class.with_file(base) do |path|
          expect(YAML.safe_load_file(path)).to eq("alice" => {"manager" => "alice"})
        end
      end
    end
  end

  it "rejects malformed or missing identity inputs" do
    Dir.mktmpdir do |tree|
      expect { described_class.build(tree) }.to raise_error(ArgumentError, /workday.yaml does not exist/)
      write_yaml(tree, "config/workday.yaml", [])
      expect { described_class.build(tree) }.to raise_error(ArgumentError, /must contain a hash/)
      write_yaml(tree, "config/workday.yaml", {"alice" => {"manager" => "alice"}})
      expect(described_class.build(tree)).to eq("alice" => {"manager" => "alice"})
      write_yaml(tree, "config/workday-overrides.yaml", {"removals" => {}})
      expect { described_class.build(tree) }.to raise_error(ArgumentError, /removals must be an array/)
    end
  end
end
