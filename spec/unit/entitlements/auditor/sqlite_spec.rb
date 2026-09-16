# frozen_string_literal: true
require_relative "../../spec_helper"

describe Entitlements::Auditor::SQLite do
  let(:stringio) { StringIO.new }
  let(:logger) { Logger.new(stringio) }
  let(:tempdir) { Dir.mktmpdir }
  let(:path) { File.join(tempdir, "entitlements.db") }
  let(:config) { { "path" => path } }
  let(:subject) { described_class.new(logger, config) }

  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }

  let(:group) do
    Entitlements::Models::Group.new(
      dn: "cn=group1,ou=Groups,dc=kittens,dc=net",
      members: Set.new(%w[blackmanx]),
      metadata: {}
    )
  end

  let(:all_groups) do
    {
      "foo" => {
        config: { "base" => "ou=Groups,dc=kittens,dc=net", "type" => "ldap" },
        groups: { "cn=group1,ou=Groups,dc=kittens,dc=net" => group }
      }
    }
  end

  before(:each) do
    allow(Entitlements::Data::Groups::Calculated).to receive(:all_groups).and_return(all_groups)
  end

  after(:each) do
    FileUtils.remove_entry_secure(tempdir) if File.directory?(tempdir)
  end

  describe "#setup" do
    it "returns nil when the configuration is valid" do
      expect(subject.setup).to be nil
    end

    it "raises when the path is not configured" do
      obj = described_class.new(logger, {})
      expect { obj.setup }.to raise_error(ArgumentError, /Not all required keys are defined. Missing: path./)
    end

    it "raises when the path is not a String" do
      obj = described_class.new(logger, { "path" => 42 })
      expect { obj.setup }.to raise_error(ArgumentError, /The 'path' must be a String, got Integer/)
    end

    it "raises when person_attributes is not an Array" do
      obj = described_class.new(logger, { "path" => path, "person_attributes" => "githubdotcomid" })
      expect { obj.setup }.to raise_error(ArgumentError, /The 'person_attributes' must be an Array, got String/)
    end

    it "raises when person_attributes contains a non-String" do
      obj = described_class.new(logger, { "path" => path, "person_attributes" => [42] })
      expect { obj.setup }.to raise_error(ArgumentError, /The 'person_attributes' must be an Array of Strings/)
    end

    it "raises when the sqlite3 gem is not installed" do
      expect(Entitlements::Graph::SQLiteWriter).to receive(:load_driver!)
        .and_raise(Entitlements::Graph::SQLiteWriter::DriverUnavailable, "the gem is missing")
      expect { subject.setup }.to raise_error(ArgumentError, /the gem is missing/)
    end
  end

  describe "#commit" do
    it "writes the graph to the configured path" do
      expect(subject.commit(actions: [], successful_actions: Set.new, provider_exception: nil)).to be nil
      expect(File.file?(path)).to eq(true)
      expect(stringio.string).to match(/Wrote 1 group\(s\) and 1 membership\(s\) to #{Regexp.escape(path)}/)
    end

    it "includes the configured person attributes" do
      obj = described_class.new(logger, { "path" => path, "person_attributes" => ["githubdotcomid"] })
      obj.commit(actions: [], successful_actions: [], provider_exception: nil)

      db = SQLite3::Database.new(path)
      expect(db.execute("SELECT value FROM person_attribute WHERE uid = 'blackmanx'").flatten).to eq(["blackmanx"])
      db.close
    end
  end
end
