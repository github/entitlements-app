# frozen_string_literal: true

# This test was inspired by a failure that occurred when the only thing that changed was
# group description (memberships and everything else stayed the same).

require_relative "spec_helper"
require "json"

# ---------------------------------------------
# First run to establish the group
# ---------------------------------------------

describe Entitlements do
  before(:all) do
    @result = run("description/before", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true)
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "logs expected messages on STDERR" do
    expect(@result.stderr).to match(log("DEBUG", "OU create_if_missing: ou=Description-Entitlements,ou=Groups,dc=kittens,dc=net needs to be created"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=kitties,ou=Description-Entitlements,ou=Groups,dc=kittens,dc=net to entitlements"))
  end

  it "populates the LDAP group with the expected members" do
    expected = %w[RAGAMUFFIn blackmanx]
    expect(members("cn=kitties,ou=Description-Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end
end

# ---------------------------------------------
# Second run to test the described edge case
# ---------------------------------------------

describe Entitlements do
  before(:all) do
    @result = run("description/after", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true)
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "logs expected messages on STDERR" do
    expect(@result.stderr).to match(log("INFO", "METADATA CHANGE cn=kitties,ou=Description-Entitlements,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("DEBUG", 'Group "entitlements" contributes 1 change\(s\).'))
  end

  it "still has the LDAP group with the expected members" do
    expected = %w[RAGAMUFFIn blackmanx]
    expect(members("cn=kitties,ou=Description-Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end
end
