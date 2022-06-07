# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::Models::Person do
  let(:uid) { "mister_fluffy" }

  let(:attribs) do
    {
      "shellentitlements" => %w[foo bar].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" },
      "someTextString"    => "kittens are awesome"
    }
  end

  describe "get and set" do
    let(:subject) { described_class.new(uid: uid, attributes: attribs) }

    it "auto-creates a previously undefined attribute in the original attributes structure" do
      subject["myNewAttribute"] = "kittens are cuddly"

      original_attributes = subject.instance_variable_get("@original_attributes")
      expect(original_attributes["myNewAttribute"]).to be nil

      current_attributes = subject.instance_variable_get("@current_attributes")
      expect(current_attributes["myNewAttribute"]).to eq("kittens are cuddly")
      expect(subject["myNewAttribute"]).to eq("kittens are cuddly")
    end

    it "raises if attempting to read an undefined variable" do
      expect { subject["thisIsUndefined"] }.to raise_error(KeyError)
    end

    it "handles strings, arrays, sets, and nil values" do
      subject["someTextString"] = nil
      subject["myNewTextString"] = "kittens are cuddly"
      subject["shellentitlements"] = %w[foo baz].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" }
      subject["setOfEntitlements"] = Set.new(%w[fizz buzz].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" })

      expect(subject["someTextString"]).to be nil
      expect(subject["myNewTextString"]).to eq("kittens are cuddly")
      expect(subject["shellentitlements"]).to eq(%w[baz foo].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" })
      expect(subject["setOfEntitlements"]).to eq(%w[buzz fizz].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" })
    end

    it "does not try to delete an entry for an entry that does not already exist" do
      subject["thisNeverExistedBefore"] = "123456"
      subject["thisNeverExistedBefore"] = nil
      expect { subject["thisNeverExistedBefore"] }.to raise_error(KeyError)
      original_attributes = subject.instance_variable_get("@original_attributes")
      expect(original_attributes.key?("thisNeverExistedBefore")).to eq(false)
    end
  end

  describe "#original" do
    let(:subject) { described_class.new(uid: uid, attributes: attribs) }

    it "returns the value from the original hash" do
      expect(subject.original("someTextString")).to eq("kittens are awesome")
      expect(subject.original("shellentitlements")).to eq(%w[bar foo].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" })
    end
  end

  describe "#attribute_changes" do
    let(:subject) { described_class.new(uid: uid, attributes: attribs) }

    it "returns an empty hash if there were no changes" do
      expect(subject.attribute_changes).to eq({})
    end

    it "does not treat a change from [] -> nil as a change" do
      subject["anEmptyArray"] = []
      expect(subject.attribute_changes).to eq({})
    end

    it "returns hash of changed key and new value" do
      subject["someTextString"] = nil
      subject["myNewTextString"] = "kittens are cuddly"
      subject["shellentitlements"] = %w[bar foo].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" }
      subject["setOfEntitlements"] = Set.new(%w[fizz buzz].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" })

      expect(subject.attribute_changes).to eq(
        "myNewTextString" => "kittens are cuddly",
        "setOfEntitlements" => %w[buzz fizz].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" },
        "someTextString" => nil
      )
    end
  end

  describe "#add" do
    let(:subject) { described_class.new(uid: uid, attributes: attribs) }

    it "raises if the current value is not found" do
      expect { subject.add("keyDoesNotExist", "kittens") }.to raise_error(KeyError)
    end

    it "raises if the current value is not a set" do
      expect do
        subject.add("someTextString", "kittens")
      end.to raise_error(ArgumentError, "Called add() on attribute that is a String")
    end

    it "adds the new value to the set" do
      subject.add("shellentitlements", "cn=bar,ou=production,dc=kittens,dc=net")
      subject.add("shellentitlements", "cn=baz,ou=production,dc=kittens,dc=net")
      expect(subject["shellentitlements"])
        .to eq(%w[bar baz foo].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" })
    end
  end

  describe "#setup_attributes" do
    it "populates @original_attributes and @current_attributes with duplicates" do
      attribs = {
        "shellentitlements" => %w[foo bar].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" },
        "someTextString"    => "kittens are awesome"
      }
      subject = described_class.new(uid: uid, attributes: attribs)

      original_attributes = subject.instance_variable_get("@original_attributes")
      current_attributes = subject.instance_variable_get("@current_attributes")

      orig = {
        "shellentitlements" => Set.new(%w[foo bar].map { |cn| "cn=#{cn},ou=production,dc=kittens,dc=net" }),
        "someTextString"    => "kittens are awesome"
      }
      expect(original_attributes).to eq(orig)
      expect(current_attributes).to eq(orig)

      current_attributes["shellentitlements"].add("cn=baz,ou=production,dc=kittens,dc=net")
      current_attributes = subject.instance_variable_get("@current_attributes")
      expect(original_attributes).to eq(orig)
      expect(current_attributes).not_to eq(orig)
    end
  end
end
