# frozen_string_literal: true

require_relative "../../../spec_helper"

describe Entitlements::Data::Groups::Cached do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj, file_objects: {} } }

  describe "#load_caches" do
    context "with predictive state directory not existing" do
      let(:dir) { fixture("non-existing-predictive-state") }

      it "raises" do
        expect do
          described_class.load_caches(dir)
        end.to raise_error(Errno::ENOENT, "No such file or directory - Predictive state directory #{dir.inspect} does not exist!")
      end
    end

    context "with valid predictive state directory" do
      let(:dir) { fixture("predictive-state/cache1") }

      it "loads the cache entries correctly and logs messages" do
        expect(logger).to receive(:debug).with("Loading predictive update caches from #{dir}")
        expect(logger).to receive(:debug).with("Loaded 3 OU(s) from cache")
        expect(logger).to receive(:debug).with("Loaded 8 DN(s) from cache")

        expect(described_class.load_caches(dir)).to be nil
      end

      it "populates :by_ou with the correct organizational units" do
        described_class.load_caches(dir)

        expect(cache[:predictive_state][:by_ou].keys.sort).to eq([
          "ou=Pizza_Teams,dc=kittens,dc=net",
          "ou=org,ou=fakegithub,dc=github,dc=fake",
          "ou=teams,ou=fakegithub,dc=github,dc=fake"
        ])
      end

      it "populates an entry in :by_ou with the correct members" do
        described_class.load_caches(dir)

        answer = ["cn=cheese", "cn=mushroom", "cn=pepperoni"]
        expect(cache[:predictive_state][:by_ou]["ou=Pizza_Teams,dc=kittens,dc=net"].keys.sort).to eq(answer)
      end

      it "populates :by_dn with the correct groups" do
        described_class.load_caches(dir)

        expect(cache[:predictive_state][:by_dn].keys.sort).to eq([
          "cn=admin,ou=org,ou=fakegithub,dc=github,dc=fake",
          "cn=cheese,ou=Pizza_Teams,dc=kittens,dc=net",
          "cn=empty,ou=teams,ou=fakegithub,dc=github,dc=fake",
          "cn=member,ou=org,ou=fakegithub,dc=github,dc=fake",
          "cn=mushroom,ou=Pizza_Teams,dc=kittens,dc=net",
          "cn=pepperoni,ou=Pizza_Teams,dc=kittens,dc=net",
          "cn=team1,ou=teams,ou=fakegithub,dc=github,dc=fake",
          "cn=team2,ou=teams,ou=fakegithub,dc=github,dc=fake"
        ])
      end

      it "populates an entry in :by_dn with the correct members" do
        described_class.load_caches(dir)

        answer = { members: Set.new(%w[korat russianblue]), metadata: { "team_id" => "9", "team_name" => "team_name" } }
        expect(cache[:predictive_state][:by_dn]["cn=cheese,ou=Pizza_Teams,dc=kittens,dc=net"]).to eq(answer)
      end

      it "handles a cache file whose membership is empty" do
        described_class.load_caches(dir)
        expect(cache[:predictive_state][:by_dn]["cn=empty,ou=teams,ou=fakegithub,dc=github,dc=fake"]).to eq({ members: Set.new, metadata: {} })
      end
    end
  end

  describe "#invalidate" do
    let(:dn) { "cn=tabbies,ou=Groups,dc=kittens,dc=net" }
    let(:members) { Set.new(%w[blackmanx ragamuffin]) }

    it "prevents future cache reads of a given DN" do
      cache[:predictive_state] = {
        by_dn: { dn => { members: members, metadata: {} } },
        invalid: Set.new
      }

      expect(described_class.members(dn)).to eq(members)

      described_class.invalidate(dn)
      expect(described_class.members(dn)).to be nil
    end
  end

  describe "#members" do
    let(:dn) { "cn=tabbies,ou=Groups,dc=kittens,dc=net" }
    let(:members) { Set.new(%w[blackmanx ragamuffin]) }

    context "with no caches loaded" do
      it "returns nil" do
        expect(described_class.members(dn)).to be nil
      end
    end

    context "with DN marked invalid" do
      it "returns nil" do
        cache[:predictive_state] = {
          by_dn: { dn => { members: Set.new, metadata: nil } },
          invalid: Set.new([dn])
        }

        expect(logger).to receive(:debug).with("members(cn=tabbies,ou=Groups,dc=kittens,dc=net): DN has been marked invalid in cache")
        expect(described_class.members(dn)).to be nil
      end
    end

    context "with DN not existing" do
      it "returns nil" do
        cache[:predictive_state] = { by_dn: {}, invalid: Set.new }

        expect(logger).to receive(:debug).with("members(cn=tabbies,ou=Groups,dc=kittens,dc=net): DN does not exist in cache")
        expect(described_class.members(dn)).to be nil
      end
    end

    context "with DN existing and valid" do
      it "returns an array of members" do
        cache[:predictive_state] = { by_dn: { dn => { members: members, metadata: {} } }, invalid: Set.new }

        result = described_class.members(dn)
        expect(result).to eq(members)
      end
    end
  end

  describe "#metadata" do
    let(:dn) { "cn=tabbies,ou=Groups,dc=kittens,dc=net" }
    let(:metadata) { { "application_owner" => "blackmanx" } }

    context "with no caches loaded" do
      it "returns nil" do
        expect(described_class.metadata(dn)).to be nil
      end
    end

    context "with DN marked invalid" do
      it "returns nil" do
        cache[:predictive_state] = {
          by_dn: { dn => { members: Set.new, metadata: nil } },
          invalid: Set.new([dn])
        }

        expect(logger).to receive(:debug).with("metadata(cn=tabbies,ou=Groups,dc=kittens,dc=net): DN has been marked invalid in cache")
        expect(described_class.metadata(dn)).to be nil
      end
    end

    context "with DN not existing" do
      it "returns nil" do
        cache[:predictive_state] = { by_dn: {}, invalid: Set.new }

        expect(logger).to receive(:debug).with("metadata(cn=tabbies,ou=Groups,dc=kittens,dc=net): DN does not exist in cache")
        expect(described_class.metadata(dn)).to be nil
      end
    end

    context "with DN existing and valid" do
      it "returns a hash of metadata" do
        cache[:predictive_state] = { by_dn: { dn => { members: Set.new, metadata: metadata } }, invalid: Set.new }

        result = described_class.metadata(dn)
        expect(result).to eq(metadata)
      end
    end
  end
end
