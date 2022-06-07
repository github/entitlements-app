# frozen_string_literal: true

require_relative "../../../../spec_helper"

describe Entitlements::Extras::LDAPGroup::Rules::LDAPGroup do
  before(:each) do
    Entitlements::Extras.load_extra("ldap_group")
    allow(described_class).to receive(:ldap).and_return(ldap)
  end

  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj, ldap_cache: ldap_cache } }
  let(:entitlements_config_file) { fixture("config-files/config-lockout.yaml") }
  let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }
  let(:ldap) { instance_double(Entitlements::Service::LDAP) }
  let(:dn) { "cn=colonel-meow,ou=Staff_Account,ou=Groups,dc=kittens,dc=net" }
  let(:file) { fixture("ldap-config/unmanaged_groups/unmanaged-group.yaml") }
  let(:entry) { instance_double(Net::LDAP::Entry) }
  let(:group) { instance_double(Entitlements::Models::Group) }
  let(:ldap_cache) { {} }
  let(:members) { %w[NEBELUNg russianblue oJosazuLEs].map { |uid| people_obj.read(uid) } }

  describe "#matches" do
    context "for a group that was cached" do
      let(:ldap_cache) { { dn => group } }

      it "returns the members" do
        expect(ldap).not_to receive(:read)
        allow(group).to receive(:members).and_return(Set.new(members))
        expect(obj.members).to eq(Set.new(members))
      end
    end

    context "for a group that was not cached" do
      it "returns the members" do
        expect(ldap).to receive(:read).with(dn).and_return(entry)
        expect(Entitlements::Service::LDAP).to receive(:entry_to_group).with(entry).and_return(group)
        allow(group).to receive(:members).and_return(Set.new(members))
        expect(obj.members).to eq(Set.new(members))
      end
    end

    context "for a group that does not exist" do
      it "raises a GroupNotFoundError" do
        expect(ldap).to receive(:read).with("cn=colonel-meow,ou=Staff_Account,ou=Groups,dc=kittens,dc=net").and_return(nil)
        expect do
          obj.members
        end.to raise_error(Entitlements::Data::Groups::GroupNotFoundError, /^Failed to read ldap_group =/)
      end
    end
  end
end
