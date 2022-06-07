# frozen_string_literal: true
require_relative "../../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Rules::Username do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }
  let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

  let(:blackmanx) { people_obj.read["blackmanx"] }
  let(:russianblue) { people_obj.read["russianblue"] }
  let(:answer_set) { Set.new([blackmanx, russianblue]) }

  describe "#matches" do
    let(:file) { fixture("ldap-config/pizza_teams/from_username.yaml") }

    context "with a matching user" do
      it "returns the matching item that matches the usernames" do
        expect(obj.members).to eq(answer_set)
      end
    end

    context "with a non-matching user" do
      let(:file) { fixture("ldap-config/pizza_teams/from_username2.yaml") }

      it "ignores the non-matching user and returns the correct set" do
        expect(obj.members).to eq(answer_set)
      end
    end
  end
end
