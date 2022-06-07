# frozen_string_literal: true

require_relative "spec_helper"

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
    expect(@result.stderr).to match(log("DEBUG", "OU create_if_missing: ou=foo-bar-app,ou=Entitlements,ou=Groups,dc=kittens,dc=net already exists"))
    expect(@result.stderr).not_to match(log("DEBUG", "APPLY:"))
  end

  it "logs appropriate informational messages to STDERR" do
    expect(@result.stderr).not_to match(log("INFO", "ADD"))
    expect(@result.stderr).to match(log("INFO", "No changes to be made. You're all set, friend!"))
  end

  it "has no 'DID NOT APPLY' warnings" do
    expect(@result.stderr).not_to match(log("WARN", "DID NOT APPLY"))
  end
end
