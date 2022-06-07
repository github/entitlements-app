# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  before(:all) do
    @result = run("multi_level", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true), @result.stderr
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "creates cn=hubber,ou=github,ou=apps correctly" do
    expect(members("cn=hubber,ou=Github,ou=Apps,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[russianblue blackmanx RAGAMUFFIn]))
  end

  it "creates cn=site1,ou=terraform,ou=apps correctly" do
    expect(members("cn=site1,ou=Terraform,ou=Apps,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[russianblue blackmanx]))
  end

  it "creates cn=site2,ou=terraform,ou=apps correctly" do
    expect(members("cn=site2,ou=Terraform,ou=Apps,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[russianblue blackmanx RAGAMUFFIn]))
  end

  it "creates cn=site3,ou=terraform,ou=apps correctly" do
    expect(members("cn=site3,ou=Terraform,ou=Apps,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[mainecoon]))
  end

  it "creates cn=wildcard,ou=terraform,ou=apps correctly" do
    expect(members("cn=wildcard,ou=Terraform,ou=Apps,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[russianblue blackmanx RAGAMUFFIn mainecoon]))
  end
end
