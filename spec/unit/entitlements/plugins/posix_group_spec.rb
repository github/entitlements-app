# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::Plugins::PosixGroup do
  it "loads and inherits" do
    expect(described_class.loaded?).to eq(true)
  end

  let(:group) { instance_double(Entitlements::Models::Group) }
  let(:ldap) { instance_double(Entitlements::Service::LDAP) }

  describe "#override_hash" do
    it "returns PosixGroup attribute override" do
      allow(ldap).to receive(:person_dn_format).and_return("uid=%KEY%,ou=People,dc=kittens,dc=net")
      people = %w[BlackManx MAINECOON]
      people_dn = people.map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }
      allow(group).to receive(:member_strings).and_return(Set.new(people))
      allow(group).to receive(:metadata).and_return("gid_number" => "12345")

      result = described_class.override_hash(group, {}, ldap)
      answer = {"objectClass"=>"PosixGroup", "memberUid"=>people_dn, "uniqueMember"=>nil, "gidNumber" => "12345", "owner" => nil}
      expect(result).to eq(answer)
    end
  end

  describe "#gid_number" do
    it "returns integer representation of GID" do
      allow(group).to receive(:metadata).and_return("gid_number" => 12345)
      result = described_class.gid_number(group)
      expect(result).to eq(12345)
    end

    it "raises an error when GID is undefined" do
      allow(group).to receive(:metadata).and_return({})
      allow(group).to receive(:dn).and_return("cn=foo,ou=bar")
      expect do
        described_class.gid_number(group)
      end.to raise_error(ArgumentError, "POSIX Group cn=foo,ou=bar has no metadata setting for gid_number!")
    end

    it "raises an error when GID is invalid" do
      allow(group).to receive(:metadata).and_return("gid_number" => 123456)
      allow(group).to receive(:dn).and_return("cn=foo,ou=bar")
      expect do
        described_class.gid_number(group)
      end.to raise_error(ArgumentError, "POSIX Group cn=foo,ou=bar has GID 123456 out of 1-65535 range!")
    end
  end
end
