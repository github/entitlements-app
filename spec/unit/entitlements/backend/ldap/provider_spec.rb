# frozen_string_literal: true
require_relative "../../../spec_helper"

describe Entitlements::Backend::LDAP::Provider do
  let(:ldap) { instance_double(Entitlements::Service::LDAP) }
  let(:stringio) { StringIO.new }
  let(:dn) { "cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net" }
  let(:snowshoe) { Entitlements::Models::Person.new(uid: "snowshoe") }
  let(:russian_blue) { Entitlements::Models::Person.new(uid: "russian_blue") }
  let(:group) { Entitlements::Models::Group.new(dn: dn, description: ":smile_cat:", members: Set.new([snowshoe, russian_blue])) }
  let(:subject) { described_class.new(ldap: ldap) }

  before(:each) do
    allow(ldap).to receive(:person_dn_format).and_return("uid=%KEY%,ou=People,dc=kittens,dc=net")
  end

  describe "#read" do
    it "raises an error if no result is found" do
      allow(ldap).to receive(:search)
        .with(base: dn, scope: 0)
        .and_return({})
      expect do
        subject.read(dn)
      end.to raise_error(Entitlements::Data::Groups::GroupNotFoundError, "No response from LDAP for dn=#{dn}")
    end

    it "returns the data from LDAP if one result is found" do
      entry = instance_double(Net::LDAP::Entry)
      result_hash = { dn => entry }
      allow(ldap).to receive(:search)
        .with(base: dn, scope: 0)
        .and_return(result_hash)
      allow(entry).to receive(:dn).and_return(dn)
      allow(entry).to receive(:[]).with(:uniquemember).and_return(["foo-bar"])
      allow(entry).to receive(:[]).with(:description).and_return([":smile_cat:"])
      allow(entry).to receive(:[]).with(:objectclass).and_return(["groupOfUniqueNames"])

      result = subject.read(dn)
      expect(result).to be_a_kind_of(Entitlements::Models::Group)
      expect(result.description).to eq(":smile_cat:")
      expect(result.dn).to eq(dn)
      expect(result.member_strings).to eq(Set.new(["foo-bar"]))
    end
  end

  describe "#read_all" do
    let(:base) { "ou=Felines,ou=Groups,dc=example,dc=net" }

    let(:dn1) { "cn=snowshoes,#{base}" }
    let(:entry1) { instance_double(Net::LDAP::Entry) }

    let(:dn2) { "cn=russian_blues,#{base}" }
    let(:entry2) { instance_double(Net::LDAP::Entry) }

    it "populates the hash from all groups in the directory" do
      allow(ldap).to receive(:search).and_return({dn1 => entry1, dn2 => entry2})
      allow(entry1).to receive(:dn).and_return(dn1)
      allow(entry1).to receive(:[]).with(:objectclass).and_return(["groupOfUniqueNames"])
      allow(entry1).to receive(:[]).with(:uniquemember).and_return(["uid=snowshoe,ou=People,dc=kittens,dc=net"])
      allow(entry1).to receive(:[]).with(:description).and_return(":smile_cat:")
      allow(entry2).to receive(:dn).and_return(dn2)
      allow(entry2).to receive(:[]).with(:objectclass).and_return(["groupOfUniqueNames"])
      allow(entry2).to receive(:[]).with(:uniquemember).and_return(["uid=russian_blue,ou=People,dc=kittens,dc=net"])
      allow(entry2).to receive(:[]).with(:description).and_return(":smile_cat:")

      result = subject.read_all(base)
      expect(result).to eq(Set.new([dn1, dn2]))
    end

    it "populates the group cache with each DN calculated along the way" do
      allow(ldap).to receive(:search).and_return({dn1 => entry1, dn2 => entry2})
      allow(entry1).to receive(:dn).and_return(dn1)
      allow(entry1).to receive(:[]).with(:objectclass).and_return(["groupOfUniqueNames"])
      allow(entry1).to receive(:[]).with(:uniquemember).and_return(["uid=snowshoe,ou=People,dc=kittens,dc=net"])
      allow(entry1).to receive(:[]).with(:description).and_return(":smile_cat:")
      allow(entry2).to receive(:dn).and_return(dn2)
      allow(entry2).to receive(:[]).with(:objectclass).and_return(["groupOfUniqueNames"])
      allow(entry2).to receive(:[]).with(:uniquemember).and_return(["uid=russian_blue,ou=People,dc=kittens,dc=net"])
      allow(entry2).to receive(:[]).with(:description).and_return(":smile_cat:")
      subject.read_all(base)

      result = Entitlements.cache[:ldap_cache]
      expect(result).to be_a_kind_of(Hash)
      expect(result.size).to eq(2)
      expect(result[dn1].member_strings).to eq(Set.new([snowshoe.uid]))
      expect(result[dn2].member_strings).to eq(Set.new([russian_blue.uid]))
    end
  end

  describe "#delete" do
    it "makes LDAP calls to delete a group" do
      expect(ldap).to receive(:delete).with(dn).and_return(true)
      expect { subject.delete(dn) }.not_to raise_error
    end

    it "raises an error if the delete fails" do
      expect(ldap).to receive(:delete).with(dn).and_return(false)
      expect { subject.delete(dn) }.to raise_error(RuntimeError, "Unable to delete LDAP group #{dn.inspect}!")
    end
  end

  describe "#upsert" do
    let(:binddn) { "uid=emmy,ou=Service_Accounts,dc=kittens,dc=net" }
    let(:upsert_attributes) do
      {
        "uniqueMember" => ["uid=snowshoe,ou=People,dc=kittens,dc=net", "uid=russian_blue,ou=People,dc=kittens,dc=net"],
        "description"  => ":smile_cat:",
        "owner"        => [binddn],
        "objectClass"  => ["groupOfUniqueNames"],
        "cn"           => "kittens"
      }
    end

    it "makes LDAP calls to upsert a group" do
      allow(ldap).to receive(:binddn).and_return(binddn)
      expect(ldap).to receive(:upsert).with(dn: dn, attributes: upsert_attributes).and_return(true)
      expect { subject.upsert(group) }.not_to raise_error
    end

    it "raises an error if the upsert fails" do
      allow(ldap).to receive(:binddn).and_return(binddn)
      expect(ldap).to receive(:upsert).with(dn: dn, attributes: upsert_attributes).and_return(false)
      expect { subject.upsert(group) }.to raise_error(RuntimeError, "Unable to upsert LDAP group #{dn.inspect}!")
    end

    it "enforces overrides" do
      overrides = { "objectClass" => ["groupOfNames"], "owner" => nil }
      allow(ldap).to receive(:binddn).and_return(binddn)
      attrs = {
        "uniqueMember" => upsert_attributes["uniqueMember"],
        "description"  => upsert_attributes["description"],
        "objectClass"  => overrides["objectClass"],
        "cn"           => upsert_attributes["cn"]
      }
      expect(ldap).to receive(:upsert).with(dn: dn, attributes: attrs).and_return(true)
      expect { subject.upsert(group, overrides) }.not_to raise_error
    end

    context "with empty group" do
      let(:group) { Entitlements::Models::Group.new(dn: dn, description: ":smile_cat:", members: Set.new) }

      let(:upsert_attributes) do
        {
          "uniqueMember" => [dn],
          "description"  => ":smile_cat:",
          "owner"        => [binddn],
          "objectClass"  => ["groupOfUniqueNames"],
          "cn"           => "kittens"
        }
      end

      it "sets the group as a member of itself" do
        allow(ldap).to receive(:binddn).and_return(binddn)
        expect(ldap).to receive(:upsert).with(dn: dn, attributes: upsert_attributes).and_return(false)
        expect { subject.upsert(group) }.to raise_error(RuntimeError, "Unable to upsert LDAP group #{dn.inspect}!")
      end
    end
  end
end
