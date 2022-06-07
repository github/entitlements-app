# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  let(:basedn) { "ou=Expiration,ou=Entitlements,ou=Groups,dc=kittens,dc=net" }

  before(:all) do
    @result = run("expiration", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true), @result.stderr
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  context "empty group" do
    it "exists" do
      expect(ldap_exist?("cn=empty,#{basedn}")).to eq(true)
    end

    it "has only itself as a member" do
      self_set = Set.new(["cn=empty,#{basedn}".downcase])
      expect(members("cn=empty,#{basedn}")).to eq(self_set)
    end
  end

  context "expired group" do
    it "exists" do
      expect(ldap_exist?("cn=expired,#{basedn}")).to eq(true)
    end

    it "has only itself as a member" do
      self_set = Set.new(["cn=expired,#{basedn}".downcase])
      expect(members("cn=expired,#{basedn}")).to eq(self_set)
    end
  end

  context "full group" do
    it "exists" do
      expect(ldap_exist?("cn=full,#{basedn}")).to eq(true)
    end

    it "has the correct member list" do
      people = people_set(%w[nebelung balinese serengeti])
      expect(members("cn=full,#{basedn}")).to eq(people)
    end
  end

  context "partial group" do
    it "exists" do
      expect(ldap_exist?("cn=partial,#{basedn}")).to eq(true)
    end

    it "has the correct member list" do
      people = people_set(%w[ragamuffin russianblue])
      expect(members("cn=partial,#{basedn}")).to eq(people)
    end
  end

  context "wildcard group" do
    it "exists" do
      expect(ldap_exist?("cn=wildcard,#{basedn}")).to eq(true)
    end

    it "has the correct member list" do
      people = people_set(%w[nebelung balinese serengeti ragamuffin russianblue])
      expect(members("cn=wildcard,#{basedn}")).to eq(people)
    end
  end
end
