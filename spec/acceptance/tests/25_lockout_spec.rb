# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  before(:all) do
    @result = run("modify_and_delete_lockout", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true)
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "logs appropriate messages to STDERR for user being removed" do
    expect(@result.stderr).to match(log("INFO", "CHANGE cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net in entitlements"))
    expect(@result.stderr).to match(log("INFO", ".  - cheetoh"))
    expect(@result.stderr).to match(log("INFO", "CHANGE cn=keyboard-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net in pizza_teams"))
    expect(@result.stderr).to match(log("INFO", "CHANGE cn=colonel-meow,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net in pizza_teams"))
  end

  it "has the correct change count" do
    # Hey there! If you are here because this test is failing, please don't blindly update the number.
    # Figure out what change you made that caused this number to increase or decrease, and add log checks
    # for it above.
    expect(@result.stderr).to match(log("INFO", "Successfully applied 4 change\\(s\\)!"))
  end

  it "implements adjustment to group containing the locked out user" do
    expect(members("cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[ojosazules nebelung khaomanee chausie cyprus]))
  end

  it "creates and populates the lockout group" do
    expect(members("cn=locked-out,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[cheetoh]))
  end

  it "implements shellentitlements changes for the locked out user" do
    user = ldap_entry("uid=cheetoh,ou=People,dc=kittens,dc=net")
    expect(user[:shellentitlements]).to eq([])
  end
end
