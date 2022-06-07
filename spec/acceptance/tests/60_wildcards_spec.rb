# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  before(:all) do
    @result = run("wildcards", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true), @result.stderr
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "creates the non-wildcard groups in their OUs" do
    expect(members("cn=one,ou=bar,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[NEBELUNg]))
    expect(members("cn=two,ou=bar,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[cheetoh]))
    expect(members("cn=three,ou=bar,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[cyprus]))
    expect(members("cn=one,ou=foo,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[blackmanx]))
    expect(members("cn=two,ou=foo,ou=Groups,dc=kittens,dc=net")).to eq(people_set(%w[mainecoon]))
  end

  it "creates a wildcard group that does not self-reference" do
    expected = %w[cheetoh cyprus]
    expect(members("cn=meta,ou=bar,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end

  it "creates a wildcard group that self-references" do
    expected = %w[cheetoh cyprus blackmanx mainecoon]
    expect(members("cn=example,ou=foo,ou=Groups,dc=kittens,dc=net")).to eq(people_set(expected))
  end
end
