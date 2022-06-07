# frozen_string_literal: true

require_relative "spec_helper"
require "open3"
require "tmpdir"

describe Entitlements do
  before(:all) do
    @result = run("initial_run", ["--debug"])
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
    expect(@result.stderr).to match(log("DEBUG", "Mirroring entitlements/mirror from entitlements/groupofnames"))
    expect(@result.stderr).to match(log("DEBUG", "APPLY: Upserting cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("DEBUG", "APPLY: Upserting cn=grumpy-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("DEBUG", "APPLY: Upserting cn=keyboard-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("DEBUG", "APPLY: Upserting cn=colonel-meow,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net"))
  end

  it "logs messages for entitlements that are created as empty due to expiration" do
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=expired-entitlement,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements (Members: )")))
  end

  it "logs appropriate informational messages to STDERR" do
    expect(@result.stderr).to match(log("INFO", "ADD cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=grumpy-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=keyboard-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=colonel-meow,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=baz,ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/foo-bar-app \\(Members: blackmanx,russianblue\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=baz,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/groupofnames \\(Members: blackmanx,russianblue\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=baz,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/mirror \\(Members: blackmanx,russianblue\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=sparkles,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/groupofnames \\(Members: RAGAMUFFIn\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD cn=sparkles,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements/mirror \\(Members: RAGAMUFFIn\\)"))
    expect(@result.stderr).to match(log("INFO", "ADD ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
    expect(@result.stderr).to match(log("INFO", "ADD ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net"))
  end

  it "has the correct change count" do
    # Hey there! If you are here because this test is failing, please don't blindly update the number.
    # Figure out what change you made that caused this number to increase or decrease, and add log checks
    # for it above.
    expect(@result.stderr).to match(log("INFO", "Successfully applied 23 change\\(s\\)!"))
  end

  it "logs appropriate informational messages to STDERR for memberOf" do
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

  it "has no 'DID NOT APPLY' warnings" do
    expect(@result.stderr).not_to match(log("WARN", "DID NOT APPLY"))
  end

  it "creates the missing OU" do
    expect(ldap_exist?("ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
  end

  it "creates the expected LDAP groups" do
    expect(ldap_exist?("cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(ldap_exist?("cn=baz,ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(ldap_exist?("cn=grumpy-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(ldap_exist?("cn=keyboard-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(ldap_exist?("cn=colonel-meow,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(true)
  end

  it "creates the mirror LDAP group" do
    expect(ldap_exist?("cn=baz,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
  end

  it "populates the group in the sub-OU with correct members" do
    expected = %w[blackmanx russianblue]
    expect(members("cn=baz,ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "populates the ruby-generated LDAP group with the expected members" do
    expected = %w[blackmanx]
    expect(members("cn=grumpy-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "populates the textfile-generated LDAP group with the expected members" do
    expected = %w[DONSKoy oregonrex oJosazuLEs NEBELUNg khaomanee chausie cheetoh cyprus]
    expect(members("cn=keyboard-cat,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "populates the YAML-generated LDAP group with the expected members" do
    expected = %w[oJosazuLEs NEBELUNg khaomanee chausie cheetoh cyprus]
    expect(members("cn=colonel-meow,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "populates the recursive YAML-generated LDAP group with the expected members" do
    expected = %w[blackmanx oJosazuLEs NEBELUNg khaomanee chausie cheetoh cyprus]
    expect(members("cn=app-aws-primary-admins,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "populates the mirror LDAP group with the expected members" do
    expected = %w[blackmanx russianblue]
    expect(members("cn=baz,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "populates the other mirror LDAP group with the expected members" do
    expected = %w[RAGAMUFFIn]
    expect(members("cn=sparkles,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "configures the mirror LDAP group using the specified plugin" do
    dn = "cn=baz,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net"

    result = ldap_entry(dn)
    expect(result).to be_a_kind_of(Net::LDAP::Entry)
    expect(result.dn).to eq(dn)

    expect(result[:objectclass]).to eq(["posixGroup"])
    expect(result[:gidnumber]).to eq(["12345"])
  end

  it "configures the other mirror LDAP group using the specified plugin" do
    dn = "cn=sparkles,ou=Mirror,ou=Entitlements,ou=Groups,dc=kittens,dc=net"

    result = ldap_entry(dn)
    expect(result).to be_a_kind_of(Net::LDAP::Entry)
    expect(result.dn).to eq(dn)

    expect(result[:objectclass]).to eq(["posixGroup"])
    expect(result[:gidnumber]).to eq(["23456"])
  end

  it "correctly builds and populates a default group" do
    dn = "cn=baz,ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net"

    result = ldap_entry(dn)
    expect(result).to be_a_kind_of(Net::LDAP::Entry)
    expect(result.dn).to eq(dn)

    expect(result[:objectclass]).to eq(["groupOfUniqueNames"])
  end

  it "correctly builds and populates the GroupOfNames group" do
    dn = "cn=baz,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net"

    result = ldap_entry(dn)
    expect(result).to be_a_kind_of(Net::LDAP::Entry)
    expect(result.dn).to eq(dn)

    expect(result[:cn]).to eq(["baz"])
    expect(result[:description]).to eq(["This is in a sub-ou"])
    expect(result[:owner]).to eq(["uid=emmy,ou=Service_Accounts,dc=kittens,dc=net"])

    expect(result[:objectclass]).to eq(["groupOfNames"])

    expected = %w[blackmanx russianblue]
    expect(members(dn)).to eq(people_set(expected))
  end

  it "sees and creates the LDAP groups for empty group testing" do
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements (Members: blackmanx)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok-2,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements (Members: RAGAMUFFIn,blackmanx)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok-3,ou=Entitlements,ou=Groups,dc=kittens,dc=net to entitlements (Members: RAGAMUFFIn)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net to pizza_teams (Members: blackmanx)")))
    expect(@result.stderr).to match(log("INFO", Regexp.escape("ADD cn=empty-but-ok-2,ou=Pizza_Teams")))

    expect(ldap_exist?("cn=empty-but-ok,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(members("cn=empty-but-ok,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[blackmanx]))
    expect(ldap_exist?("cn=empty-but-ok-2,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(members("cn=empty-but-ok-2,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[RAGAMUFFIn blackmanx]))
    expect(ldap_exist?("cn=empty-but-ok-3,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(members("cn=empty-but-ok-3,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[RAGAMUFFIn]))
    expect(ldap_exist?("cn=empty-but-ok,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(members("cn=empty-but-ok,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[blackmanx]))
    expect(ldap_exist?("cn=empty-but-ok-2,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(members("cn=empty-but-ok-2,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(Set.new(%w[cn=empty-but-ok-2,ou=pizza_teams,ou=groups,dc=kittens,dc=net]))
  end

  it "creates expired LDAP group as empty" do
    expect(ldap_exist?("cn=expired-entitlement,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(members("cn=expired-entitlement,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(Set.new(%w[cn=expired-entitlement,ou=entitlements,ou=groups,dc=kittens,dc=net]))
  end

  it "seeds the LDAP group for subsequent expiration testing" do
    expect(ldap_exist?("cn=expire-later,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(true)
    expect(members("cn=expire-later,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[blackmanx nebelung]))
  end

  it "updates the attributes using the memberOf functionality" do
    ragamuffin = ldap_entry("uid=ragamuffin,ou=People,dc=kittens,dc=net")
    expect(ragamuffin[:shellentitlements]).to eq(["cn=sparkles,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net"])
  end

  it "updates the attributes using the memberOf functionality" do
    blackmanx = ldap_entry("uid=blackmanx,ou=People,dc=kittens,dc=net")
    expect(blackmanx[:shellentitlements]).to eq(["cn=baz,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net"])
  end

  it "updates the attributes using the memberOf functionality" do
    russianblue = ldap_entry("uid=russianblue,ou=People,dc=kittens,dc=net")
    expect(russianblue[:shellentitlements]).to eq(["cn=baz,ou=GroupOfNames,ou=Entitlements,ou=Groups,dc=kittens,dc=net"])
  end

  it "leaves users untouched who did not belong to memberOf groups" do
    cheetoh = ldap_entry("uid=cheetoh,ou=People,dc=kittens,dc=net")
    expect(cheetoh[:cn]).to eq(["cheetoh"])
    expect(cheetoh[:shellentitlements]).to eq([])
  end
end
