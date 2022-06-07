# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::Plugins::GroupOfNames do
  it "loads and inherits" do
    expect(described_class.loaded?).to eq(true)
  end

  let(:group) { instance_double(Entitlements::Models::Group) }
  let(:ldap) { instance_double(Entitlements::Service::LDAP) }

  describe "#override_hash" do
    it "returns GroupOfNames attribute override" do
      allow(ldap).to receive(:person_dn_format).and_return("uid=%KEY%,ou=People,dc=kittens,dc=net")
      people = %w[BlackManx MAINECOON]
      people_dn = people.map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }
      allow(group).to receive(:member_strings).and_return(Set.new(people))

      result = described_class.override_hash(group, {}, ldap)
      expect(result).to eq({"objectClass"=>"GroupOfNames", "member"=>people_dn, "uniqueMember"=>nil})
    end
  end
end
