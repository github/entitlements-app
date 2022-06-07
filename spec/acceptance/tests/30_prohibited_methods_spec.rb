# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  context "with a disallowed method" do
    before(:all) do
      @result = run("prohibited_methods", ["--debug"])
    end

    it "returns failure" do
      expect(@result.success?).to eq(false)
    end

    it "logs the fatal exception for the prohibited method" do
      expect(@result.stderr).to match(log("FATAL", "The method \"group\" is not permitted in .+/illegal.yaml!"))
    end
  end

  context "with ruby disallowed" do
    before(:all) do
      @result = run("prohibited_ruby", ["--debug"])
    end

    it "returns failure" do
      expect(@result.success?).to eq(false)
    end

    it "logs the fatal exception for the prohibited file" do
      expect(@result.stderr).to match(log("FATAL", "Files with extension \"rb\" are not allowed in this OU! Allowed: txt,yaml!"))
    end
  end

  context "with a text file containing an invalid method" do
    before(:all) do
      @result = run("text_file_invalid_method", ["--debug"])
    end

    it "returns failure" do
      expect(@result.success?).to eq(false)
    end

    it "logs the fatal exception for the prohibited file" do
      expect(@result.stderr).to match(log("FATAL", "The method \"contractor\" is not permitted in .*invalid.txt!"))
    end
  end
end
