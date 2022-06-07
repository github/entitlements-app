# frozen_string_literal: true

require_relative "../../../../spec_helper"

describe Entitlements::Extras::Orgchart::Rules::Management do
  before(:each) do
    Entitlements::Extras.load_extra("orgchart")
  end

  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }

  context "with an actual manager" do
    let(:file) { fixture("ldap-config/pizza_teams/from_management.yaml") }
    let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

    describe "#matches" do
      it "returns the manager and all of their reports" do
        result = %w[DONSKoy oJosazuLEs NEBELUNg cyprus cheetoh khaomanee chausie oregonrex]
        answer_set = Set.new(result.map { |name| people_obj.read(name) })
        expect(obj.members).to eq(answer_set)
      end
    end
  end

  context "with a non-manager" do
    let(:file) { fixture("ldap-config/pizza_teams/from_management_not.yaml") }
    let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

    describe "#matches" do
      it "raises a fatal exception" do
        expect(logger).to receive(:fatal).with(/Manager BlackManx has no reports/)
        expect { obj.members }.to raise_error(/Manager BlackManx has no reports/)
      end
    end
  end

  context "with a manager that no longer exists in LDAP" do
    let(:file) { fixture("ldap-config/pizza_teams/from_management_gone.yaml") }
    let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

    describe "#matches" do
      it "raises a fatal exception" do
        expect(logger).to receive(:fatal).with(/Manager .*hubot.* does not exist/)
        expect { obj.members }.to raise_error(/Manager .*hubot.* does not exist/)
      end
    end
  end
end
