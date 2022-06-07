# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  context "with a configuration that deals with LDAP groups and contractors" do
    before(:all) do
      @result = run("groups_and_contractors", ["--debug"])
    end

    it "returns success" do
      expect(@result.success?).to eq(true), @result.stderr
    end

    it "prints nothing on STDOUT" do
      expect(@result.stdout).to eq("")
    end

    it "handles contractors=all" do
      expected = %w[pixiebob serengeti blackmanx mainecoon]
      expect(members("cn=contractors-all,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles contractors=none" do
      expected = %w[blackmanx mainecoon]
      expect(members("cn=contractors-none,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "treats no declaration of contractors as contractors=none" do
      expected = %w[blackmanx mainecoon]
      expect(members("cn=contractors-not-specified,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (users only) (one in list)" do
      expected = %w[blackmanx mainecoon pixiebob]
      expect(members("cn=contractors-named-users-one,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (users only) (all in list)" do
      expected = %w[blackmanx mainecoon pixiebob serengeti]
      expect(members("cn=contractors-named-users-two,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (users only) (more in list)" do
      expected = %w[blackmanx mainecoon pixiebob serengeti]
      expect(members("cn=contractors-named-users-more,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (users only) (none in list)" do
      expected = %w[blackmanx mainecoon]
      expect(members("cn=contractors-named-users-none,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (groups only) (one in list)" do
      expected = %w[blackmanx mainecoon pixiebob]
      expect(members("cn=contractors-named-groups-one,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (groups only) (two in list)" do
      expected = %w[blackmanx mainecoon pixiebob serengeti]
      expect(members("cn=contractors-named-groups-two,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (groups only) (more in list)" do
      expected = %w[blackmanx mainecoon pixiebob serengeti]
      expect(members("cn=contractors-named-groups-more,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (groups only) (none in list)" do
      expected = %w[blackmanx mainecoon]
      expect(members("cn=contractors-named-groups-none,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles named contractors (users and groups)" do
      expected = %w[blackmanx mainecoon pixiebob serengeti]
      expect(members("cn=contractors-named-groups-more,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles doubly-listed contractors" do
      expected = %w[blackmanx mainecoon pixiebob]
      expect(members("cn=contractors-double-list,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles non-expired contractors" do
      expected = %w[blackmanx mainecoon pixiebob serengeti]
      expect(members("cn=contractors-expiration-not,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "behaves as if contractors=none when an 'all' is expired" do
      expected = %w[blackmanx mainecoon]
      expect(members("cn=contractors-expiration-all,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "behaves as if contractors=none when all individual entries are expired" do
      expected = %w[blackmanx mainecoon]
      expect(members("cn=contractors-expiration-none,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "keeps non-expired contractors but removes expired ones" do
      expected = %w[blackmanx mainecoon serengeti]
      expect(members("cn=contractors-expiration-mixed,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end
  end
end
