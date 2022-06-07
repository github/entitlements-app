# frozen_string_literal: true
require_relative "../../../spec_helper"

describe Entitlements::Data::People::LDAP do
  let(:ldap) { instance_double(Entitlements::Service::LDAP) }
  let(:people_ou) { "ou=People,dc=kittens,dc=net" }
  let(:uid1) { "evilmanx" }
  let(:dn1) { "uid=#{uid1},#{people_ou}" }
  let(:uid2) { "evilragamuffin" }
  let(:dn2) { "uid=#{uid2},#{people_ou}" }
  let(:subject) { described_class.new(ldap: ldap, people_ou: people_ou) }

  describe "#fingerprint" do
    let(:config) do
      {
        "ldap_uri"         => "ldaps://ldap.kittens.net",
        "ldap_binddn"      => "uid=binder,ou=People,dc=kittens,dc=net",
        "ldap_bindpw"      => "s3cr3t",
        "person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net",
        "base"             => "ou=People,dc=kittens,dc=net"
      }
    end

    let(:answer) { "\"ou=People,dc=kittens,dc=net\"||\"uid=binder,ou=People,dc=kittens,dc=net\"||\"s3cr3t\"||\"ldaps://ldap.kittens.net\"||nil||\"uid=%KEY%,ou=People,dc=kittens,dc=net\"||nil||nil||nil" }

    it "returns a fingerprint based on serialized attributes" do
      expect(described_class.fingerprint(config)).to eq(answer)
    end
  end

  describe "#initialize" do
    it "prefers a People OU set as a constructor argument" do
      Entitlements.config_file = fixture("config-files/config-ldap-ou.yaml")
      ldap = instance_double(Entitlements::Service::LDAP)
      subject = described_class.new(ldap: ldap, people_ou: "ou=People,dc=fluffy,dc=net")
      expect(subject.send(:people_ou)).to eq("ou=People,dc=fluffy,dc=net")
    end
  end

  describe "#read" do
    before(:each) do
      Entitlements.config_file = fixture("config.yaml")

      entry1 = instance_double(Net::LDAP::Entry)
      allow(entry1).to receive(:dn).and_return(dn1)
      allow(entry1).to receive(:[]).with(:cn).and_return(["Evil Bacon"])

      entry2 = instance_double(Net::LDAP::Entry)
      allow(entry2).to receive(:dn).and_return(dn2)
      allow(entry2).to receive(:[]).with(:cn).and_return(["Evil Bacon"])

      search_result = { uid1 => entry1, uid2 => entry2 }
      allow(ldap).to receive(:search)
        .with(base: people_ou, filter: Net::LDAP::Filter.eq("uid", "*"), attrs: %w[cn])
        .and_return(search_result)
    end

    it "reads the entire OU and returns a hash of person objects" do
      expect(subject.read.keys).to eq([uid1, uid2])
      expect(subject.read[uid1]).to be_a_kind_of(Entitlements::Models::Person)
      expect(subject.read[uid1].uid).to eq(uid1)
      expect(subject.read[uid2]).to be_a_kind_of(Entitlements::Models::Person)
      expect(subject.read[uid2].uid).to eq(uid2)
    end

    it "reads a specific entry from LDAP in a case-insensitive manner and returns that one result" do
      result = subject.read(uid1)
      expect(result).to be_a_kind_of(Entitlements::Models::Person)
      expect(result.uid).to eq(uid1)
    end

    it "raises an error if directed to read an entry that does not exist" do
      expect do
        subject.read("BozoTheClown")
      end.to raise_error(Entitlements::Data::People::NoSuchPersonError)
    end

    context "with custom attributes in the configuration" do
      let(:subject) { described_class.new(ldap: ldap, people_ou: people_ou, people_attr: custom_attributes) }

      let(:custom_attributes) do
        %w[cn shellentitlements randomText]
      end

      it "reads in custom attributes" do
        entry1 = instance_double(Net::LDAP::Entry)
        allow(entry1).to receive(:dn).and_return(dn1)
        allow(entry1).to receive(:[]).with(:cn).and_return(["Evil Bacon"])
        allow(entry1).to receive(:[]).with(:shellentitlements).and_return(["cn=shell5", "cn=shell3"])
        allow(entry1).to receive(:[]).with(:randomText).and_return(nil)

        entry2 = instance_double(Net::LDAP::Entry)
        allow(entry2).to receive(:dn).and_return(dn2)
        allow(entry2).to receive(:[]).with(:cn).and_return(["Evil Bacon"])
        allow(entry2).to receive(:[]).with(:shellentitlements).and_return([])
        allow(entry2).to receive(:[]).with(:randomText).and_return("Hi there")

        search_result = { uid1 => entry1, uid2 => entry2 }
        allow(ldap).to receive(:search)
          .with(
            base: people_ou,
            filter: Net::LDAP::Filter.eq("uid", "*"),
            attrs: custom_attributes.sort
          ).and_return(search_result)

        result1 = subject.read("evilmanx")
        expect { result1["randomText"] }.to raise_error(KeyError)
        expect(result1["shellentitlements"]).to eq(%w[cn=shell3 cn=shell5])

        result2 = subject.read("evilragamuffin")
        expect(result2["randomText"]).to eq("Hi there")
        expect(result2["shellentitlements"]).to eq([])
      end
    end
  end
end
