# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::Data::People do
  describe "#class_for_config" do
    context "when the incoming request lacks a type" do
      let(:request) { { "name" => "bob", "config" => {} } }

      it "raises" do
        expect do
          described_class.class_for_config(request)
        end.to raise_error(ArgumentError, "'type' is undefined in: {\"name\"=>\"bob\", \"config\"=>{}}")
      end
    end

    context "when the type in the incoming request is invalid" do
      let(:request) { { "name" => "bob", "config" => {}, "type" => "kitten" } }

      it "raises" do
        expect { described_class.class_for_config(request) }.to raise_error(ArgumentError, "'type' \"kitten\" is invalid!")
      end
    end

    context "when the type in the incoming request is valid" do
      let(:request) { { "name" => "bob", "config" => {}, "type" => "ldap" } }

      it "returns the class" do
        expect(described_class.class_for_config(request)).to eq(Entitlements::Data::People::LDAP)
      end
    end
  end

  describe "#new_from_config" do
    let(:config_1) { { "filename" => "/tmp/yaml1.yaml" } }
    let(:cfg_1) { { "type" => "yaml", "config" => config_1 } }

    let(:config_2) { { "filename" => "/tmp/yaml2.yaml" } }
    let(:cfg_2) { { "type" => "yaml", "config" => config_2 } }

    let(:config_3) do
      {
        "ldap_uri"         => "ldaps://ldap.kittens.net",
        "ldap_binddn"      => "uid=binder,ou=People,dc=kittens,dc=net",
        "ldap_bindpw"      => "s3cr3t",
        "person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net",
        "base"             => "ou=People,dc=kittens,dc=net"
      }
    end
    let(:cfg_3) { { "type" => "ldap", "config" => config_3 } }

    let(:result_1) { instance_double(Entitlements::Data::People::YAML) }
    let(:result_2) { instance_double(Entitlements::Data::People::YAML) }
    let(:result_3) { instance_double(Entitlements::Data::People::LDAP) }

    it "constructs underlying objects without duplication" do
      allow(Entitlements::Data::People::YAML).to receive(:new_from_config).with(config_1).and_return(result_1)
      allow(Entitlements::Data::People::YAML).to receive(:new_from_config).with(config_2).and_return(result_2)
      allow(Entitlements::Data::People::LDAP).to receive(:new_from_config).with(config_3).and_return(result_3)

      allow(Entitlements::Data::People::YAML).to receive(:fingerprint).with(config_1).and_return("config_1")
      allow(Entitlements::Data::People::YAML).to receive(:fingerprint).with(config_2).and_return("config_2")
      allow(Entitlements::Data::People::LDAP).to receive(:fingerprint).with(config_3).and_return("config_3")

      expect(described_class.new_from_config(cfg_1)).to eq(result_1)
      expect(described_class.new_from_config(cfg_1)).to eq(result_1)
      expect(described_class.new_from_config(cfg_2)).to eq(result_2)
      expect(described_class.new_from_config(cfg_3)).to eq(result_3)
    end
  end
end
