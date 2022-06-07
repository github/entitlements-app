# frozen_string_literal: true

require_relative "../../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:mygroup_obj) { instance_double(Entitlements::Data::Groups::Calculated::Text) }
  let(:cache) do
    {
      people_obj: people_obj,
      file_objects: { fixture("ldap-config/internal/mygroup") => mygroup_obj },
      calculated: { "internal" => { "mygroup" => groupdef } }
    }
  end
  let(:config) { { "group" => "internal/mygroup" } }
  let(:groupdef) do
    Set.new([
      people_obj.read("chartreux"),
      people_obj.read("dwelf")
    ])
  end

  before(:each) do
    setup_default_filters
  end

  context "with a :none filter" do
    let(:subject) { described_class.new(filter: :none, config: config) }

    describe "filtered?" do
      it "returns true for a user in the group" do
        allow(mygroup_obj).to receive(:members).and_return(groupdef)
        allow(mygroup_obj).to receive(:modified_members).and_return(groupdef)
        person = people_obj.read("chartreux")
        expect(subject.filtered?(person)).to eq(true)
      end

      it "returns true for a user in the group" do
        allow(mygroup_obj).to receive(:members).and_return(groupdef)
        allow(mygroup_obj).to receive(:modified_members).and_return(groupdef)
        person = people_obj.read("dwelf")
        expect(subject.filtered?(person)).to eq(true)
      end

      it "returns false for a user not in the group" do
        allow(mygroup_obj).to receive(:members).and_return(groupdef)
        allow(mygroup_obj).to receive(:modified_members).and_return(groupdef)
        person = people_obj.read("BlackManx")
        expect(subject.filtered?(person)).to eq(false)
      end
    end
  end

  context "with a matching per-username filter" do
    let(:subject) { described_class.new(filter: %w[CHARTREUx], config: config) }

    describe "filtered?" do
      it "returns false for a matching user in the group" do
        allow(mygroup_obj).to receive(:members).and_return(groupdef)
        allow(mygroup_obj).to receive(:modified_members).and_return(groupdef)
        person = people_obj.read("chartreux")
        expect(subject.filtered?(person)).to eq(false)
      end

      it "returns true for a non-matching user in the group" do
        allow(mygroup_obj).to receive(:members).and_return(groupdef)
        allow(mygroup_obj).to receive(:modified_members).and_return(groupdef)
        person = people_obj.read("dwelf")
        expect(subject.filtered?(person)).to eq(true)
      end

      it "returns false for a user not in the group" do
        allow(mygroup_obj).to receive(:members).and_return(groupdef)
        allow(mygroup_obj).to receive(:modified_members).and_return(groupdef)
        person = people_obj.read("BlackManx")
        expect(subject.filtered?(person)).to eq(false)
      end
    end
  end
end
