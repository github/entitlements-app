# frozen_string_literal: true

require_relative "../../../../spec_helper"

describe Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj, ldap_cache: ldap_cache } }
  let(:config) { { "ldap_group" => "cn=mygroup,ou=Groups,dc=kittens,dc=net" } }
  let(:entitlements_config_file) { fixture("config-files/config-lockout.yaml") }
  let(:ldap_cache) { {} }

  before(:each) do
    Entitlements::Extras.load_extra("ldap_group")
    setup_default_filters

    allow(Entitlements::Extras::LDAPGroup::Rules::LDAPGroup).to receive(:matches).and_return(Set.new([
      people_obj.read("chartreux"),
      people_obj.read("dwelf")
    ]))
  end

  context "with a :none filter" do
    let(:subject) { described_class.new(filter: :none, config: config) }

    describe "filtered?" do
      it "returns true for a user in the group" do
        person = people_obj.read("chartreux")
        expect(subject.filtered?(person)).to eq(true)
      end

      it "returns true for a user in the group" do
        person = people_obj.read("dwelf")
        expect(subject.filtered?(person)).to eq(true)
      end

      it "returns false for a user not in the group" do
        person = people_obj.read("BlackManx")
        expect(subject.filtered?(person)).to eq(false)
      end
    end
  end

  context "with a matching per-username filter" do
    let(:subject) { described_class.new(filter: %w[CHARTREUx], config: config) }

    describe "filtered?" do
      it "returns false for a matching user in the group" do
        person = people_obj.read("chartreux")
        expect(subject.filtered?(person)).to eq(false)
      end

      it "returns true for a non-matching user in the group" do
        person = people_obj.read("dwelf")
        expect(subject.filtered?(person)).to eq(true)
      end

      it "returns false for a user not in the group" do
        person = people_obj.read("BlackManx")
        expect(subject.filtered?(person)).to eq(false)
      end
    end
  end

  describe "#member_of_ldap_group?" do
    let(:manx) { people_obj.read("blackmanx") }
    let(:ragamuffin) { people_obj.read("ragamuffin") }
    let(:dn) { "cn=lockout,ou=Groups,dc=kittens,dc=net" }
    let(:subject) { described_class.new(filter: :none, config: config) }
    let(:group) { instance_double(Entitlements::Models::Group) }

    context "when group does not exist" do
      it "returns false" do
        expect(Entitlements::Extras::LDAPGroup::Rules::LDAPGroup).to receive(:matches)
          .with(value: dn).and_raise(Entitlements::Data::Groups::GroupNotFoundError)

        result = subject.send(:member_of_ldap_group?, ragamuffin, dn)
        expect(result).to eq(false)
      end
    end

    context "when group exists" do
      let(:members) { Set.new([ragamuffin]) }

      it "returns false when person is not a member" do
        expect(Entitlements::Extras::LDAPGroup::Rules::LDAPGroup).to receive(:matches).with(value: dn).and_return(members)
        result = subject.send(:member_of_ldap_group?, manx, dn)
        expect(result).to eq(false)
      end

      it "returns true when person is a member" do
        expect(Entitlements::Extras::LDAPGroup::Rules::LDAPGroup).to receive(:matches).with(value: dn).and_return(members)
        result = subject.send(:member_of_ldap_group?, ragamuffin, dn)
        expect(result).to eq(true)
      end
    end
  end
end
