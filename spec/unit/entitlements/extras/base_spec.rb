# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::Extras::Base do
  before(:each) do
    Entitlements::Extras.load_extra("orgchart")
  end

  let(:subject) { Entitlements::Extras::Orgchart::Base }

  describe "#config" do
    context "with no extras config at all" do
      let(:entitlements_config_hash) { {} }

      it "returns {}" do
        expect(subject.config).to eq({})
      end
    end

    context "with no config for the extra" do
      let(:entitlements_config_hash) do
        { "extras" => { "foo" => "bar" } }
      end

      it "returns {}" do
        expect(subject.config).to eq({})
      end
    end

    context "with a non-hash config for the extra" do
      let(:entitlements_config_hash) do
        { "extras" => { "orgchart" => "bar" } }
      end

      it "returns {}" do
        expect(subject.config).to eq({})
      end
    end

    context "with a hash config for the extra" do
      let(:entitlements_config_hash) do
        { "extras" => { "orgchart" => { "foo" => "bar" } } }
      end

      it "returns config" do
        expect(subject.config).to eq("foo" => "bar")
      end
    end
  end
end
