# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  context "logic tests" do
    before(:all) do
      @result = run("logic", ["--debug"])
    end

    it "returns success" do
      expect(@result.success?).to eq(true), @result.stderr
    end

    it "prints nothing on STDOUT" do
      expect(@result.stdout).to eq("")
    end

    it "creates the expected single condition group" do
      expected = %w[ragamuffin mainecoon]
      expect(members("cn=single-condition,ou=Logic,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "creates the expected multi condition group (1)" do
      expected = %w[ragamuffin mainecoon nebelung ojosazules donskoy]
      expect(members("cn=multi-condition-1,ou=Logic,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "creates the expected multi condition group (2)" do
      expected = %w[ragamuffin mainecoon nebelung donskoy]
      expect(members("cn=multi-condition-2,ou=Logic,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
    end

    it "handles the expected no-member group" do
      expect(ldap_exist?("cn=no-match,ou=Logic,ou=Entitlements,dc=kittens,dc=net")).to eq(false)
    end
  end
end
