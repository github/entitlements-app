# frozen_string_literal: true

require_relative "../../../spec_helper"
require_relative "../../../../../lib/entitlements/models/person"

describe Entitlements::Extras::Orgchart::PersonMethods do
  before(:each) do
    Entitlements::Extras.load_extra("orgchart")
  end

  let(:manager_map) { fixture("manager-map.yaml") }
  let(:config) do
    {
      "extras" => {
        "orgchart" => {
          "manager_map_file" => manager_map
        }
      }
    }
  end
  let(:entitlements_config_hash) { config }
  let(:uid) { "ragamuffin" }
  let(:uid2) { "fluffywhiskers" }
  let(:person) { Entitlements::Models::Person.new(uid: uid) }
  let(:person2) { Entitlements::Models::Person.new(uid: uid2) }

  describe "#manager" do
    context "when the manager map file is not defined" do
      let(:entitlements_config_hash) { config.merge("extras" => { "orgchart" => {} }) }

      it "raises" do
        message = "To use Entitlements::Extras::Orgchart::PersonMethods, `manager_map_file` must be defined in the configuration!"
        expect { person.manager }.to raise_error(ArgumentError, message)
      end
    end

    context "when the manager map file does not exist" do
      let(:manager_map) { fixture("non-existing-file.yaml") }

      it "raises" do
        message = %r{No such file or directory - The `manager_map_file` .+/fixtures/non-existing-file.yaml does not exist!}
        expect { person.manager }.to raise_error(Errno::ENOENT, message)
      end
    end

    context "when the user does not exist in manager map" do
      it "raises" do
        message = "User fluffywhiskers is not included in manager map data!"
        expect { person2.manager }.to raise_error(RuntimeError, message)
      end
    end

    context "when the user's manager is undefined in manager map" do
      let(:manager_map) { fixture("bad-manager-map.yaml") }

      it "raises" do
        message = "User ragamuffin does not have a manager listed in manager map data!"
        expect { person.manager }.to raise_error(RuntimeError, message)
      end
    end

    context "when the manager map file has proper data" do
      it "returns the user's manager as per manager map" do
        expect(person.manager).to eq("mainecoon")
      end
    end
  end
end
