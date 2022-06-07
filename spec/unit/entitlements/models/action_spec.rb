# frozen_string_literal: true
require_relative "../../spec_helper"

describe Entitlements::Models::Action do

  let(:dn) { "cn=foo,ou=bar,dc=kittens,dc=net" }
  let(:ou) { "bar" }
  let(:existing) { instance_double(Entitlements::Models::Group) }
  let(:updated) { instance_double(Entitlements::Models::Group) }

  let(:subject) { described_class.new(dn, existing, updated, ou) }

  describe "#initialize" do
    context "without ignored users" do
      it "returns an empty set for ignored_users" do
        expect(subject.ignored_users).to eq(Set.new)
      end
    end

    context "with ignored users" do
      let(:subject) { described_class.new(dn, existing, updated, ou, ignored_users: ignored_users) }
      let(:ignored_users) { Set.new(%w[foo bar baz]) }

      it "accepts and reflects ignored_users" do
        expect(subject.ignored_users).to eq(ignored_users)
      end
    end
  end

  describe "#change_type" do
    context "for an addition" do
      let(:existing) { nil }

      it "returns :add" do
        expect(subject.change_type).to eq(:add)
      end
    end

    context "for a removal" do
      let(:updated) { nil }

      it "returns :delete" do
        expect(subject.change_type).to eq(:delete)
      end
    end

    context "for an update" do
      it "returns :update" do
        expect(subject.change_type).to eq(:update)
      end
    end
  end

  describe "#short_name" do
    it "returns the first attribute for an expected-format DN" do
      expect(subject.short_name).to eq("foo")
    end

    context "when pattern does not match" do
      let(:dn) { "kittens,cats" }

      it "returns the full DN" do
        expect(subject.short_name).to eq(dn)
      end
    end
  end
end
