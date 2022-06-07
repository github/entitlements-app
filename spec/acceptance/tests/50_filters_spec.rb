# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  before(:all) do
    @result = run("filters", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true), @result.stderr
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "does not include contractors or pre-hires in the pizza team" do
    expected = %w[blackmanx]
    expect(members("cn=garfield,ou=Pizza_Teams,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "correctly creates an employees-only group" do
    expected = %w[blackmanx]
    expect(members("cn=employees-only,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "correctly creates an employees+contractors group" do
    expected = %w[blackmanx pixiebob]
    expect(members("cn=employees-contractors,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "correctly creates an employees+pre-hires group" do
    expected = %w[blackmanx chartreux]
    expect(members("cn=employees-prehires,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "correctly creates an employees+contractors group" do
    expected = %w[blackmanx pixiebob chartreux]
    expect(members("cn=employees-contractors-prehires,ou=Entitlements,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end
end
