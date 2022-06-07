# frozen_string_literal: true

require_relative "../../../spec_helper"

describe Entitlements::Data::People::YAML do
  let(:subject) { described_class.new(filename: fixture("people.yaml")) }

  describe "#fingerprint" do
    let(:config) { { "filename" => "/tmp/foo.yaml" } }
    let(:answer) { '"/tmp/foo.yaml"' }

    it "returns a fingerprint based on serialized attributes" do
      expect(described_class.fingerprint(config)).to eq(answer)
    end
  end

  describe "#read" do
    context "reading with no uid" do
      it "returns the hash of username => person object" do
        result = subject.read
        expect(result).to be_a_kind_of(Hash)
        expect(result.keys.size).to eq(27)
        expect(result.fetch("pixiEbob")).to be_a_kind_of(Entitlements::Models::Person)
      end
    end

    context "reading with a specified uid" do
      it "returns the username's person object" do
        result = subject.read("pixiEbob")
        expect(result).to be_a_kind_of(Entitlements::Models::Person)
        expect(result.uid).to eq("pixiEbob")
      end

      it "is case insensitive" do
        result = subject.read("pixiebob")
        expect(result).to be_a_kind_of(Entitlements::Models::Person)
        expect(result.uid).to eq("pixiEbob")
      end

      it "raises if the username is not found" do
        expect do
          subject.read("non-existing-user")
        end.to raise_error(Entitlements::Data::People::NoSuchPersonError)
      end
    end
  end
end
