# frozen_string_literal: true

# This is the simplest invocation of the CLI, just to make sure everything works as it should.

require_relative "spec_helper"

describe Entitlements do
  let(:dn) { "uid=emmy,ou=Service_Accounts,dc=kittens,dc=net" }

  context "normal output mode" do
    before(:all) do
      @result = run("basic_execution_no_action")
    end

    it "returns exit status 0" do
      expect(@result.exitstatus).to eq(0)
    end

    it "returns success" do
      expect(@result.success?).to eq(true)
    end

    it "prints nothing on STDOUT" do
      expect(@result.stdout).to eq("")
    end

    it "prints expected message on STDERR" do
      expect(@result.stderr).to match(log("INFO", "No changes to be made. You're all set, friend! :sparkles:"))
    end
  end

  context "debug output mode" do
    before(:all) do
      @result = run("basic_execution_no_action", ["--debug"])
    end

    it "returns exit status 0" do
      expect(@result.exitstatus).to eq(0)
    end

    it "returns success" do
      expect(@result.success?).to eq(true)
    end

    it "prints nothing on STDOUT" do
      expect(@result.stdout).to eq("")
    end

    it "prints expected messages on STDERR" do
      expect(@result.stderr).to match(log("DEBUG", "Creating connection to ldap-server.fake port 636"))
      expect(@result.stderr).to match(log("DEBUG", 'Binding with user "uid=emmy,ou=Service_Accounts,dc=kittens,dc=net"'))
      expect(@result.stderr).to match(log("DEBUG", "Successfully authenticated to ldap-server.fake port 636"))
      expect(@result.stderr).to match(log("DEBUG", 'Completed search: \d\d+ result\(s\)'))
      expect(@result.stderr).to match(log("INFO", "No changes to be made. You're all set, friend! :sparkles:"))
    end
  end
end
