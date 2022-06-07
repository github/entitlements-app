# frozen_string_literal: true

require_relative "spec_helper"
require "json"

describe Entitlements do
  before(:all) do
    @result = run("initial_run", ["--debug", "--noop"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true)
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "logs appropriate debug messages to STDERR" do
    expect(@result.stderr).to match(log("DEBUG", "Loading all groups for ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("DEBUG", "Loading all groups for ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("DEBUG", "OU create_if_missing: ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net needs to be created"))
    expect(@result.stderr).not_to match(log("DEBUG", "APPLY: Upserting"))
  end

  it "logs messages related to memberOf attributes to STDERR" do
    expect(@result.stderr).to match(log("DEBUG", "Calculating memberOf attributes for configured groups"))
    expect(@result.stderr).to match(log("INFO", "Person blackmanx attribute change:"))
    expect(@result.stderr).to match(log("INFO", ". (ADD|MODIFY) attribute shellentitlements:"))
    expect(@result.stderr).to match(log("INFO", '.  \\+ "cn=baz,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net"'))
    expect(@result.stderr).to match(log("INFO", "Person russianblue attribute change:"))
    expect(@result.stderr).to match(log("INFO", ". (ADD|MODIFY) attribute shellentitlements:"))
    expect(@result.stderr).to match(log("INFO", '.  \\+ "cn=baz,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net"'))
    expect(@result.stderr).to match(log("INFO", "Person RAGAMUFFIn attribute change:"))
    expect(@result.stderr).to match(log("INFO", ". (ADD|MODIFY) attribute shellentitlements:"))
    expect(@result.stderr).to match(log("INFO", '.  \\+ "cn=sparkles,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net"'))
    expect(@result.stderr).not_to match(log("INFO", "Person foldex attribute change:"))
  end

  it "logs appropriate informational messages to STDERR" do
    expect(@result.stderr).to match(log("INFO", "ADD cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements \\(Members: NEBELUNg,blackmanx,chausie,cheetoh,cyprus,khaomanee,oJosazuLEs\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=grumpy-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams \\(Members: blackmanx\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=keyboard-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams \\(Members: DONSKoy,NEBELUNg,chausie,cheetoh,cyprus,khaomanee,oJosazuLEs,oregonrex\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=colonel-meow,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams \\(Members: NEBELUNg,chausie,cheetoh,cyprus,khaomanee,oJosazuLEs\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=baz,ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/foo-bar-app \\(Members: blackmanx,russianblue\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("INFO", "ADD ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=baz,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/groupofnames \\(Members: blackmanx,russianblue\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=baz,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/mirror \\(Members: blackmanx,russianblue\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=sparkles,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/groupofnames \\(Members: RAGAMUFFIn\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=sparkles,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/mirror \\(Members: RAGAMUFFIn\\)"))
  end

  it "has the correct change count" do
    # Hey there! If you are here because this test is failing, please don't blindly update the number.
    # Figure out what change you made that caused this number to increase or decrease, and add log checks
    # for it above.
    expect(@result.stderr).to match(log("INFO", "No-op mode is set. Would make 23 change\\(s\\)"))
  end

  it "does not actually create the missing OUs" do
    expect(ldap_exist?("ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
  end

  it "does not actually create any LDAP groups" do
    # Created by initial setup
    expect(ldap_exist?("ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(true)

    # Created by entitlements app, but not in no-op mode
    expect(ldap_exist?("cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("cn=grumpy-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("cn=keyboard-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("cn=colonel-meow,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(false)

    # Mirror OU
    expect(ldap_exist?("cn=baz,ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("cn=baz,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
  end

  it "sees but does not create the LDAP groups expected for empty group testing" do
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements (Members: blackmanx)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok-2,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements (Members: RAGAMUFFIn,blackmanx)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok-3,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements (Members: RAGAMUFFIn)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams (Members: blackmanx)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok-2,ou=Pizza_Teams")))

    expect(ldap_exist?("cn=empty-but-ok,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("cn=empty-but-ok-2,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("cn=empty-but-ok-3,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(false)
    expect(ldap_exist?("cn=empty-but-ok,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(false)
  end

  it "does not make updates with the memberOf functionality" do
    ragamuffin = ldap_entry("uid=ragamuffin,ou=People,dc=kittens,dc=net")
    expect(ragamuffin[:cn]).to eq(["RAGAMUFFIn"])
    expect(ragamuffin[:shellentitlements]).to eq([])
  end
end
