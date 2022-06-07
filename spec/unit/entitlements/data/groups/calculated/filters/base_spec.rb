# frozen_string_literal: true

require_relative "../../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Filters::Base do
  before(:each) do
    Entitlements::Extras.load_extra("ldap_group")
  end

  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj, calculated: calculated, file_objects: {} } }
  let(:subject) { Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup.new(filter: :none) }
  let(:calculated) { {} }

  describe "#member_of_named_group?" do
    it "returns true if the named group exists and the person is a member" do
      fake_group = "pizza_teams/from_username"
      person = people_obj.read("blackmanx")
      result = subject.send(:member_of_named_group?, person, fake_group)
      expect(result).to eq(true)
    end

    it "returns false if the named group exists and the person is not a member" do
      fake_group = "pizza_teams/from_username"
      person = people_obj.read("ragamuffin")
      result = subject.send(:member_of_named_group?, person, fake_group)
      expect(result).to eq(false)
    end

    it "raises if the named group does not exist" do
      fake_group = "pizza_teams/non-existing-team"
      person = people_obj.read("pixiebob")
      expect { subject.send(:member_of_named_group?, person, fake_group) }.to raise_error(
        RuntimeError, %r{Error: Could not find a configuration for .+/pizza_teams/non-existing-team}
      )
    end
  end

  describe "#member_of_filter?" do
    it "returns true when a person is on a list of usernames" do
      arg = %w[BLACKMANX ragamuffin maiNecOon]
      person = people_obj.read("blackmanx")
      subject = described_class.new(filter: arg)
      expect(subject.send(:member_of_filter?, person)).to eq(true)
    end

    it "returns true when a person is on a list of usernames + groups" do
      arg = %w[BLACKMANX ragamuffin maiNecOon foo/baz fizz/buzz]
      person = people_obj.read("blackmanx")
      subject = described_class.new(filter: arg)
      expect(subject.send(:member_of_filter?, person)).to eq(true)
    end

    it "returns false when a person is not on a list of usernames" do
      arg = %w[BLACKMANX ragamuffin maiNecOon]
      person = people_obj.read("russianblue")
      subject = described_class.new(filter: arg)
      expect(subject.send(:member_of_filter?, person)).to eq(false)
    end

    it "returns false when a person is not on a list of usernames + groups" do
      arg = %w[BLACKMANX ragamuffin maiNecOon pizza_teams/from_username2]
      person = people_obj.read("peterbald")
      subject = described_class.new(filter: arg)
      expect(subject.send(:member_of_filter?, person)).to eq(false)
    end

    it "returns true when a person is in a group" do
      arg = %w[BLACKMANX ragamuffin maiNecOon pizza_teams/from_username2]
      person = people_obj.read("russianblue")
      subject = described_class.new(filter: arg)
      expect(subject.send(:member_of_filter?, person)).to eq(true)
    end
  end
end
