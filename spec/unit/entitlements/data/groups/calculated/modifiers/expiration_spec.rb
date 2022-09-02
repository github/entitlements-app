# frozen_string_literal: true

require_relative "../../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Modifiers::Expiration do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }
  let(:ou_key) { "expiration" }
  let(:cfg_obj) { { "base" => "ou=Felines,ou=Groups,dc=example,dc=net" } }
  let(:config) { "2043-01-01" }
  let(:rs) { instance_double(Entitlements::Data::Groups::Calculated::Ruby) }
  let(:subject) { described_class.new(rs: rs, config: config) }

  describe "#modify" do
    context "non-expired text file" do
      it "returns the members" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=valid-text,ou=Felines,ou=Groups,dc=example,dc=net")

        expected_result = %w[blackmanx RAGAMUFFIn]
        answer_set = Set.new(expected_result.map { |name| people_obj.read[name] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "expired text file" do
      it "returns an empty set" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=expired-text,ou=Felines,ou=Groups,dc=example,dc=net")
        expect(obj.members).to eq(Set.new)
      end

      it "returns members if expiration is disabled in the configuration" do
        Entitlements.config["ignore_expirations"] = true
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=expired-text,ou=Felines,ou=Groups,dc=example,dc=net")
        expected_result = %w[russianblue mainecoon]
        answer_set = Set.new(expected_result.map { |name| people_obj.read[name] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "expired text file with no valid non-expired conditions" do
      it "returns an empty set" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=expired-text-empty,ou=Felines,ou=Groups,dc=example,dc=net")
        expect(obj.members).to eq(Set.new)
      end
    end

    context "non-expired non-expired yaml file (date as date)" do
      it "returns the members" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=valid-yaml,ou=Felines,ou=Groups,dc=example,dc=net")

        expected_result = %w[mainecoon]
        answer_set = Set.new(expected_result.map { |name| people_obj.read[name].uid })
        expect(obj.member_strings).to eq(answer_set)
      end
    end

    context "expired yaml file (date as date)" do
      it "returns an empty set" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=expired-yaml,ou=Felines,ou=Groups,dc=example,dc=net")
        expect(obj.members).to eq(Set.new)
      end
    end

    context "non-expired yaml file (date as string)" do
      it "returns the members" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=valid-yaml-quoted-date,ou=Felines,ou=Groups,dc=example,dc=net")

        expected_result = %w[oJosazuLEs]
        answer_set = Set.new(expected_result.map { |name| people_obj.read[name].uid })
        expect(obj.member_strings).to eq(answer_set)
      end
    end

    context "expired yaml file (date as string)" do
      it "returns an empty set" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key).and_return(fixture("ldap-config/#{ou_key}"))
        Entitlements::Data::Groups::Calculated.read_all(ou_key, cfg_obj)
        obj = Entitlements::Data::Groups::Calculated.read("cn=expired-yaml-quoted-date,ou=Felines,ou=Groups,dc=example,dc=net")
        expect(obj.members).to eq(Set.new)
      end
    end
  end
end
