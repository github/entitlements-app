# frozen_string_literal: true
require_relative "../../spec_helper"

describe Entitlements::Graph::Snapshot do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }

  let(:group_one) do
    Entitlements::Models::Group.new(
      dn: "cn=group1,ou=Groups,dc=kittens,dc=net",
      members: Set.new(%w[blackmanx RAGAMUFFIn]),
      description: "Group One",
      metadata: { "_filename" => "/tmp/entitlements/foo/group1.txt", "team_name" => "kittens", "extra" => ["a", "b"] }
    )
  end

  let(:group_two) do
    Entitlements::Models::Group.new(
      dn: "cn=group2,ou=Groups,dc=kittens,dc=net",
      members: Set.new(%w[blackmanx]),
      description: "Group Two"
    )
  end

  let(:all_groups) do
    {
      "foo" => {
        config: { "base" => "ou=Groups,dc=kittens,dc=net", "type" => "ldap" },
        groups: {
          "cn=group2,ou=Groups,dc=kittens,dc=net" => group_two,
          "cn=group1,ou=Groups,dc=kittens,dc=net" => group_one
        }
      }
    }
  end

  let(:cache) { { people_obj: people_obj } }

  before(:each) do
    allow(Entitlements::Data::Groups::Calculated).to receive(:all_groups).and_return(all_groups)
  end

  describe "run metadata" do
    it "records the version, schema version, and configuration path" do
      subject = described_class.new
      expect(subject.run["entitlements_version"]).to eq(Entitlements::Version::VERSION)
      expect(subject.run["schema_version"]).to eq(described_class::SCHEMA_VERSION)
      expect(subject.run["generated_at"]).to eq("2018-04-01T12:00:00Z")
      expect(subject.run["configuration_path"]).to eq(Entitlements.config_path)
      expect(subject.run["provider_exception"]).to be nil
    end

    it "records a provider exception when one occurred" do
      subject = described_class.new(provider_exception: RuntimeError.new("kaboom"))
      expect(subject.run["provider_exception"]).to eq("RuntimeError: kaboom")
    end
  end

  describe "groups" do
    let(:subject) { described_class.new }

    it "records the OUs" do
      expect(subject.ous).to eq(
        [{ "ou_key" => "foo", "base_dn" => "ou=Groups,dc=kittens,dc=net", "type" => "ldap" }]
      )
    end

    it "records the groups sorted by DN" do
      expect(subject.groups.map { |g| g["dn"] }).to eq(
        ["cn=group1,ou=Groups,dc=kittens,dc=net", "cn=group2,ou=Groups,dc=kittens,dc=net"]
      )
      expect(subject.groups.first).to eq(
        "dn" => "cn=group1,ou=Groups,dc=kittens,dc=net",
        "cn" => "group1",
        "ou_key" => "foo",
        "description" => "Group One",
        "filename" => "/tmp/entitlements/foo/group1.txt"
      )
      expect(subject.groups.last["filename"]).to be nil
    end

    it "records the metadata excluding the internal filename key" do
      expect(subject.group_metadata).to eq(
        [
          { "dn" => "cn=group1,ou=Groups,dc=kittens,dc=net", "key" => "extra", "value" => "[\"a\",\"b\"]" },
          { "dn" => "cn=group1,ou=Groups,dc=kittens,dc=net", "key" => "team_name", "value" => "kittens" }
        ]
      )
    end

    it "records the memberships sorted" do
      expect(subject.memberships).to eq(
        [
          { "group_dn" => "cn=group1,ou=Groups,dc=kittens,dc=net", "uid" => "RAGAMUFFIn" },
          { "group_dn" => "cn=group1,ou=Groups,dc=kittens,dc=net", "uid" => "blackmanx" },
          { "group_dn" => "cn=group2,ou=Groups,dc=kittens,dc=net", "uid" => "blackmanx" }
        ]
      )
    end

    context "with a group that has no members and does not permit that" do
      let(:group_two) do
        Entitlements::Models::Group.new(
          dn: "cn=group2,ou=Groups,dc=kittens,dc=net",
          members: Set.new,
          metadata: { "no_members_ok" => false }
        )
      end

      it "records no memberships for that group rather than raising" do
        expect(subject.memberships.map { |m| m["group_dn"] }.uniq).to eq(
          ["cn=group1,ou=Groups,dc=kittens,dc=net"]
        )
      end
    end

    context "with metadata values of assorted types" do
      let(:group_two) do
        Entitlements::Models::Group.new(
          dn: "cn=group2,ou=Groups,dc=kittens,dc=net",
          members: Set.new(%w[blackmanx]),
          metadata: {
            "a_symbol" => :kittens,
            "a_number" => 42,
            "a_boolean" => false,
            "a_nil" => nil,
            "a_set" => Set.new(%w[b a]),
            "a_hash" => { "x" => "y" }
          }
        )
      end

      it "stringifies the values" do
        values = subject.group_metadata
          .select { |row| row["dn"] == "cn=group2,ou=Groups,dc=kittens,dc=net" }
          .map { |row| [row["key"], row["value"]] }.to_h

        expect(values).to eq(
          "a_symbol" => "kittens",
          "a_number" => "42",
          "a_boolean" => "false",
          "a_nil" => "",
          "a_set" => "[\"b\",\"a\"]",
          "a_hash" => "{\"x\":\"y\"}"
        )
      end
    end
  end

  describe "people" do
    it "records everyone from the people data source and all group members" do
      subject = described_class.new
      uids = subject.people.map { |person| person["uid"] }
      expect(uids).to include("blackmanx")
      expect(uids).to include("RAGAMUFFIn")
      expect(uids).to eq(uids.sort)
      expect(subject.person_attributes).to eq([])
    end

    it "records the allowlisted person attributes only" do
      extra_person = Entitlements::Models::Person.new(
        uid: "russianblue",
        attributes: { "githubdotcomid" => "russianblue", "roles" => %w[beta alpha], "manager" => "bengal" }
      )
      allow(people_obj).to receive(:read).and_return("russianblue" => extra_person)

      subject = described_class.new(person_attributes: %w[roles githubdotcomid nonexistent-attribute])
      expect(subject.person_attributes).to eq(
        [
          { "uid" => "russianblue", "name" => "githubdotcomid", "value" => "russianblue" },
          { "uid" => "russianblue", "name" => "roles", "value" => "alpha" },
          { "uid" => "russianblue", "name" => "roles", "value" => "beta" }
        ]
      )
    end

    context "with no people data source in the cache" do
      let(:cache) { {} }

      it "records the people referenced by memberships" do
        subject = described_class.new(person_attributes: %w[shellentitlements])
        expect(subject.people.map { |person| person["uid"] }).to eq(["RAGAMUFFIn", "blackmanx"])
        expect(subject.person_attributes).to eq([])
      end
    end
  end

  describe "dependencies" do
    let(:cache) do
      {
        people_obj: people_obj,
        group_dependencies: Set.new(
          [
            ["foo/group1", "foo/group2"],
            ["foo/group1", "bar/other"]
          ]
        )
      }
    end

    it "resolves references to DNs where possible" do
      subject = described_class.new
      expect(subject.dependencies).to eq(
        [
          {
            "parent_reference" => "foo/group1",
            "child_reference" => "bar/other",
            "parent_dn" => "cn=group1,ou=Groups,dc=kittens,dc=net",
            "child_dn" => nil
          },
          {
            "parent_reference" => "foo/group1",
            "child_reference" => "foo/group2",
            "parent_dn" => "cn=group1,ou=Groups,dc=kittens,dc=net",
            "child_dn" => "cn=group2,ou=Groups,dc=kittens,dc=net"
          }
        ]
      )
    end
  end

  describe "actions" do
    let(:updated) do
      Entitlements::Models::Group.new(
        dn: "cn=group1,ou=Groups,dc=kittens,dc=net",
        members: Set.new(%w[blackmanx russianblue])
      )
    end

    let(:existing) do
      Entitlements::Models::Group.new(
        dn: "cn=group1,ou=Groups,dc=kittens,dc=net",
        members: Set.new(%w[blackmanx mainecoon])
      )
    end

    let(:update_action) do
      Entitlements::Models::Action.new("cn=group1,ou=Groups,dc=kittens,dc=net", existing, updated, "foo")
    end

    let(:delete_action) do
      Entitlements::Models::Action.new("cn=group2,ou=Groups,dc=kittens,dc=net", existing, nil, "foo")
    end

    let(:person_action) do
      Entitlements::Models::Action.new("uid=blackmanx,ou=People,dc=kittens,dc=net", :none, people_obj.read("blackmanx"), "foo")
    end

    it "records the actions and the membership changes" do
      subject = described_class.new(
        actions: [delete_action, update_action, person_action],
        successful_actions: Set.new(["cn=group1,ou=Groups,dc=kittens,dc=net"])
      )

      expect(subject.actions).to eq(
        [
          { "dn" => "cn=group1,ou=Groups,dc=kittens,dc=net", "ou_key" => "foo", "change_type" => "update", "applied" => 1 },
          { "dn" => "cn=group2,ou=Groups,dc=kittens,dc=net", "ou_key" => "foo", "change_type" => "delete", "applied" => 0 }
        ]
      )

      expect(subject.action_members).to eq(
        [
          { "dn" => "cn=group1,ou=Groups,dc=kittens,dc=net", "uid" => "russianblue", "change_type" => "add" },
          { "dn" => "cn=group1,ou=Groups,dc=kittens,dc=net", "uid" => "mainecoon", "change_type" => "remove" },
          { "dn" => "cn=group2,ou=Groups,dc=kittens,dc=net", "uid" => "blackmanx", "change_type" => "remove" },
          { "dn" => "cn=group2,ou=Groups,dc=kittens,dc=net", "uid" => "mainecoon", "change_type" => "remove" }
        ]
      )
    end

    it "records an add action with no existing group" do
      add_action = Entitlements::Models::Action.new("cn=group3,ou=Groups,dc=kittens,dc=net", nil, updated, "foo")
      subject = described_class.new(actions: [add_action], successful_actions: [])
      expect(subject.actions).to eq(
        [{ "dn" => "cn=group3,ou=Groups,dc=kittens,dc=net", "ou_key" => "foo", "change_type" => "add", "applied" => 0 }]
      )
      expect(subject.action_members.map { |row| row["uid"] }).to eq(%w[blackmanx russianblue])
    end
  end
end
