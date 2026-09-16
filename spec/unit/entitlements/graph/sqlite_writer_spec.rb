# frozen_string_literal: true
require_relative "../../spec_helper"

require "sqlite3"

describe Entitlements::Graph::SQLiteWriter do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }

  let(:parent_group) do
    Entitlements::Models::Group.new(
      dn: "cn=parent,ou=Groups,dc=kittens,dc=net",
      members: Set.new(%w[blackmanx]),
      description: "Parent",
      metadata: { "_filename" => "/tmp/foo/parent.txt", "team_name" => "kittens" }
    )
  end

  let(:child_group) do
    Entitlements::Models::Group.new(
      dn: "cn=child,ou=Groups,dc=kittens,dc=net",
      members: Set.new(%w[RAGAMUFFIn]),
      description: "Child",
      metadata: {}
    )
  end

  let(:empty_group) do
    Entitlements::Models::Group.new(
      dn: "cn=empty,ou=Groups,dc=kittens,dc=net",
      members: Set.new,
      description: "Empty",
      metadata: {}
    )
  end

  let(:all_groups) do
    {
      "foo" => {
        config: { "base" => "ou=Groups,dc=kittens,dc=net", "type" => "ldap" },
        groups: {
          "cn=parent,ou=Groups,dc=kittens,dc=net" => parent_group,
          "cn=child,ou=Groups,dc=kittens,dc=net" => child_group,
          "cn=empty,ou=Groups,dc=kittens,dc=net" => empty_group
        }
      }
    }
  end

  let(:cache) do
    {
      people_obj: people_obj,
      group_dependencies: Set.new([["foo/parent", "foo/child"]])
    }
  end

  let(:action) do
    Entitlements::Models::Action.new(
      "cn=parent,ou=Groups,dc=kittens,dc=net",
      Entitlements::Models::Group.new(dn: "cn=parent,ou=Groups,dc=kittens,dc=net", members: Set.new(%w[mainecoon])),
      parent_group,
      "foo"
    )
  end

  let(:snapshot) do
    Entitlements::Graph::Snapshot.new(
      actions: [action],
      successful_actions: Set.new(["cn=parent,ou=Groups,dc=kittens,dc=net"]),
      person_attributes: %w[githubdotcomid]
    )
  end

  let(:tempdir) { Dir.mktmpdir }
  let(:path) { File.join(tempdir, "subdir", "entitlements.db") }

  before(:each) do
    allow(Entitlements::Data::Groups::Calculated).to receive(:all_groups).and_return(all_groups)
  end

  after(:each) do
    FileUtils.remove_entry_secure(tempdir) if File.directory?(tempdir)
  end

  describe "#driver_available?" do
    it "returns true when the sqlite3 gem can be loaded" do
      expect(described_class.driver_available?).to eq(true)
    end

    it "returns false when the sqlite3 gem cannot be loaded" do
      expect(described_class).to receive(:require).with("sqlite3").and_raise(LoadError, "no such file")
      expect(described_class.driver_available?).to eq(false)
    end
  end

  describe "#load_driver!" do
    it "raises DriverUnavailable when the gem is missing" do
      expect(described_class).to receive(:require).with("sqlite3").and_raise(LoadError, "no such file")
      expect { described_class.load_driver! }.to raise_error(
        described_class::DriverUnavailable, /The sqlite3 gem is required.+no such file/
      )
    end
  end

  describe "#write!" do
    it "creates the destination directory and writes the file atomically" do
      expect(described_class.new(snapshot).write!(path)).to eq(path)
      expect(File.file?(path)).to eq(true)
      expect(Dir.glob(File.join(File.dirname(path), "*.tmp.*"))).to eq([])
    end

    it "records the schema version and application ID" do
      described_class.new(snapshot).write!(path)
      db = SQLite3::Database.new(path)
      expect(db.execute("PRAGMA user_version").flatten.first).to eq(Entitlements::Graph::Snapshot::SCHEMA_VERSION)
      expect(db.execute("PRAGMA application_id").flatten.first).to eq(described_class::APPLICATION_ID)
      db.close
    end

    it "records the nodes, edges, and actions" do
      described_class.new(snapshot).write!(path)
      db = SQLite3::Database.new(path)

      expect(db.execute("SELECT generated_at, entitlements_version FROM run")).to eq(
        [["2018-04-01T12:00:00Z", Entitlements::Version::VERSION]]
      )
      expect(db.execute("SELECT ou_key, base_dn, type FROM ou")).to eq(
        [["foo", "ou=Groups,dc=kittens,dc=net", "ldap"]]
      )
      expect(db.execute("SELECT dn FROM \"group\" ORDER BY dn").flatten).to eq(
        [
          "cn=child,ou=Groups,dc=kittens,dc=net",
          "cn=empty,ou=Groups,dc=kittens,dc=net",
          "cn=parent,ou=Groups,dc=kittens,dc=net"
        ]
      )
      expect(db.execute("SELECT key, value FROM group_metadata")).to eq([["team_name", "kittens"]])
      expect(db.execute("SELECT group_dn, uid FROM membership ORDER BY group_dn, uid")).to eq(
        [
          ["cn=child,ou=Groups,dc=kittens,dc=net", "RAGAMUFFIn"],
          ["cn=parent,ou=Groups,dc=kittens,dc=net", "blackmanx"]
        ]
      )
      expect(db.execute("SELECT parent_dn, child_dn FROM group_dependency")).to eq(
        [["cn=parent,ou=Groups,dc=kittens,dc=net", "cn=child,ou=Groups,dc=kittens,dc=net"]]
      )
      expect(db.execute("SELECT dn, change_type, applied FROM action")).to eq(
        [["cn=parent,ou=Groups,dc=kittens,dc=net", "update", 1]]
      )
      expect(db.execute("SELECT uid, change_type FROM action_member ORDER BY uid")).to eq(
        [["blackmanx", "add"], ["mainecoon", "remove"]]
      )
      expect(db.execute("SELECT value FROM person_attribute WHERE uid = 'blackmanx'").flatten).to eq(["blackmanx"])

      db.close
    end

    it "supports recursive expansion of group references" do
      described_class.new(snapshot).write!(path)
      db = SQLite3::Database.new(path)

      expect(db.execute("SELECT ancestor_dn, descendant_dn, depth FROM group_dependency_closure")).to eq(
        [["cn=parent,ou=Groups,dc=kittens,dc=net", "cn=child,ou=Groups,dc=kittens,dc=net", 1]]
      )
      expect(
        db.execute("SELECT uid FROM expanded_membership WHERE group_dn = 'cn=parent,ou=Groups,dc=kittens,dc=net' ORDER BY uid").flatten
      ).to eq(%w[RAGAMUFFIn blackmanx])
      expect(db.execute("SELECT dn FROM empty_group").flatten).to eq(["cn=empty,ou=Groups,dc=kittens,dc=net"])
      expect(db.execute("SELECT cn FROM person_entitlement WHERE uid = 'blackmanx'").flatten).to eq(["parent"])

      db.close
    end

    it "terminates on a circular group reference" do
      cache[:group_dependencies] = Set.new([["foo/parent", "foo/child"], ["foo/child", "foo/parent"]])
      described_class.new(snapshot).write!(path)
      db = SQLite3::Database.new(path)

      rows = db.execute("SELECT ancestor_dn, descendant_dn FROM group_dependency_closure ORDER BY ancestor_dn, descendant_dn")
      expect(rows.size).to eq(4)
      db.close
    end

    it "produces byte-identical files for identical input" do
      first = File.join(tempdir, "first.db")
      second = File.join(tempdir, "second.db")
      described_class.new(snapshot).write!(first)
      described_class.new(snapshot).write!(second)
      expect(File.read(first, mode: "rb")).to eq(File.read(second, mode: "rb"))
    end

    it "cleans up the temporary file when the write fails" do
      expect(FileUtils).to receive(:mv).and_raise(Errno::EACCES, "denied")
      expect { described_class.new(snapshot).write!(path) }.to raise_error(Errno::EACCES)
      expect(Dir.glob(File.join(File.dirname(path), "*"))).to eq([])
    end

    it "raises DriverUnavailable when the gem is missing" do
      expect(described_class).to receive(:require).with("sqlite3").and_raise(LoadError, "no such file")
      expect { described_class.new(snapshot).write!(path) }.to raise_error(described_class::DriverUnavailable)
    end
  end
end
