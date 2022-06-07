# frozen_string_literal: true
require_relative "../../spec_helper"
require "logger"
require "stringio"

describe Entitlements::Backend::BaseProvider do

  subject { described_class.new }

  describe "#diff" do
    it "returns the correct case-insensitive hash" do
      old_grp = Entitlements::Models::Group.new(
        dn: "cn=diff-cats,ou=Github,dc=github,dc=fake",
        members: Set.new(%w[cuddles fluffy morris WHISKERS].map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }),
        metadata: { "team_id" => 10005 }
      )

      new_grp = Entitlements::Models::Group.new(
        dn: "cn=diff-cats,ou=Github,dc=github,dc=fake",
        members: Set.new(%w[cuddles fluffy Mittens WHISKERS].map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }),
        metadata: { "team_id" => 10005 }
      )

      allow(subject).to receive(:read).with("diff-cats").and_return(old_grp)

      result = subject.diff(new_grp)
      expect(result).to eq(
        added: Set.new(%w[uid=Mittens,ou=People,dc=kittens,dc=net]),
        removed: Set.new(%w[uid=morris,ou=People,dc=kittens,dc=net])
      )
    end
  end

  describe "#diff_existing_updated" do
    it "returns the correct case-insensitive hash" do
      old_grp = Entitlements::Models::Group.new(
        dn: "cn=diff-cats,ou=Github,dc=github,dc=fake",
        members: Set.new(%w[cuddles fluffy morris WHISKERS].map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }),
        metadata: { "team_id" => 10005 }
      )

      new_grp = Entitlements::Models::Group.new(
        dn: "cn=diff-cats,ou=Github,dc=github,dc=fake",
        members: Set.new(%w[cuddles fluffy Mittens WHISKERS].map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }),
        metadata: { "team_id" => 10005 }
      )

      result = subject.diff_existing_updated(old_grp, new_grp)
      expect(result).to eq(
        added: Set.new(%w[uid=Mittens,ou=People,dc=kittens,dc=net]),
        removed: Set.new(%w[uid=morris,ou=People,dc=kittens,dc=net])
      )
    end
  end

  it "filters out ignored users" do
    old_grp = Entitlements::Models::Group.new(
      dn: "cn=diff-cats,ou=Github,dc=github,dc=fake",
      members: Set.new(%w[cuddles fluffy morris WHISKERS fuRRy].map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }),
      metadata: { "team_id" => 10005 }
    )

    new_grp = Entitlements::Models::Group.new(
      dn: "cn=diff-cats,ou=Github,dc=github,dc=fake",
      members: Set.new(%w[cuddles fluffy Mittens WHISKERS sNuGGles].map { |u| "uid=#{u},ou=People,dc=kittens,dc=net" }),
      metadata: { "team_id" => 10005 }
    )

    allow(subject).to receive(:read).with("diff-cats").and_return(old_grp)

    ignored_users = Set.new(%w[mittens morris])

    result = subject.diff(new_grp, ignored_users)
    expect(result).to eq(
      added: Set.new(%w[uid=sNuGGles,ou=People,dc=kittens,dc=net]),
      removed: Set.new(%w[uid=fuRRy,ou=People,dc=kittens,dc=net])
    )
  end
end
