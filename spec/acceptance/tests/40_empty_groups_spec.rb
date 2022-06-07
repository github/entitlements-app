# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  context "with a configuration that has a group with no conditions" do
    before(:all) do
      @result = run("empty_group", ["--debug"])
    end

    it "returns failure" do
      expect(@result.success?).to eq(false)
    end

    it "logs the fatal exception for the group that has no conditions" do
      expect(@result.stderr).to match(log("FATAL", "No conditions were found in .+/keyboard-cat\\.txt"))
    end
  end

  context "with a configuration that has a group with no matching users" do
    before(:all) do
      @result = run("empty_group_contractor", ["--debug"])
    end

    it "returns success" do
      expect(@result.success?).to eq(true)
    end

    it "contains appropriate log entries" do
      expect(@result.stderr).to match(log("INFO", "DELETE cn=multi-condition-1,ou=Logic,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
      expect(@result.stderr).to match(log("INFO", "DELETE cn=multi-condition-2,ou=Logic,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
      expect(@result.stderr).not_to match(log("INFO", "DELETE cn=single-condition,ou=Logic,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
      expect(@result.stderr).not_to match(log("INFO", "APPLY: Deleting cn=single-condition"))
    end

    it "updates the self-referencing group" do
      dn = "cn=single-condition,ou=Logic,ou=Entitlements,ou=Groups,dc=kittens,dc=net"
      expect(members(dn)).to eq(Set.new([dn.downcase]))
    end

    it "does not create an empty group where no group existed before" do
      expect(ldap_exist?("cn=no-match,ou=Logic,ou=Entitlements,dc=kittens,dc=net")).to eq(false)
    end
  end
end
