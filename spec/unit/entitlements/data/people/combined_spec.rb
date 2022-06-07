# frozen_string_literal: true

require_relative "../../../spec_helper"

describe Entitlements::Data::People::Combined do
  let(:combined_config) do
    {
      "operator" => "or",
      "components" => [
        {
          "type" => "combined",
          "name" => "combined_1",
          "config" => {
            "operator" => "and",
            "components" => [
              {
                "type"   => "yaml",
                "name"   => "YAML data source 1",
                "config" => {
                  "filename"         => "/tmp/foo.yaml",
                  "person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net"
                }
              },
              {
                "type"   => "ldap",
                "name"   => "LDAP data source 1",
                "config" => {
                  "ldap_uri"         => "ldaps://ldap.kittens.net",
                  "ldap_binddn"      => "uid=binder,ou=People,dc=kittens,dc=net",
                  "ldap_bindpw"      => "s3cr3t",
                  "person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net",
                  "base"             => "ou=People,dc=kittens,dc=net"
                }
              }
            ]
          }
        },
        {
          "type"   => "yaml",
          "name"   => "YAML data source 2",
          "config" => {
            "filename"         => "/tmp/foo2.yaml",
            "person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net"
          }
        }
      ]
    }
  end

  let(:subject) { described_class.new(operator: operator, components: components) }
  let(:operator) { "and" }
  let(:components) { [combined_config["components"][0]["config"]["components"][0]] }
  let(:ldap_1) { combined_config["components"][0]["config"]["components"][1]["config"] }
  let(:yaml_1) { combined_config["components"][0]["config"]["components"][0]["config"] }
  let(:yaml_2) { combined_config["components"][1]["config"] }
  let(:ldap_obj_1) { instance_double(Entitlements::Data::People::LDAP) }
  let(:yaml_obj_1) { instance_double(Entitlements::Data::People::YAML) }
  let(:yaml_obj_2) { instance_double(Entitlements::Data::People::YAML) }
  let(:person_1) { instance_double(Entitlements::Models::Person) }
  let(:person_2) { instance_double(Entitlements::Models::Person) }
  let(:person_3) { instance_double(Entitlements::Models::Person) }
  let(:person_4) { instance_double(Entitlements::Models::Person) }

  describe "#fingerprint" do
    let(:answer) { "{\"or\":[\"{\\\"and\\\":[\\\"YAML1\\\",\\\"LDAP1\\\"]}\",\"YAML2\"]}" }

    it "serializes the combined configuration using JSON" do
      expect(Entitlements::Data::People::LDAP).to receive(:fingerprint).with(ldap_1).and_return("LDAP1")
      expect(Entitlements::Data::People::YAML).to receive(:fingerprint).with(yaml_1).and_return("YAML1")
      expect(Entitlements::Data::People::YAML).to receive(:fingerprint).with(yaml_2).and_return("YAML2")
      expect(described_class.fingerprint(combined_config)).to eq(answer)
    end
  end

  describe "#validate_config!" do
    context "with an invalid operator" do
      let(:config) { combined_config.merge("operator" => "kitten") }

      it "raises" do
        expect do
          described_class.validate_config!("foo", config)
        end.to raise_error(ArgumentError, "In foo, expected 'operator' to be either 'and' or 'or', not \"kitten\"!")
      end
    end

    context "with an invalid (non-Hash/non-String) component" do
      let(:config) { combined_config.merge("components" => [[]]) }

      it "raises" do
        expect do
          described_class.validate_config!("foo", config)
        end.to raise_error(ArgumentError, "In foo, expected array of hashes/strings but got []!")
      end
    end

    context "with an empty array of components" do
      let(:config) { combined_config.merge("components" => []) }

      it "raises" do
        expect do
          described_class.validate_config!("foo", config)
        end.to raise_error(ArgumentError, "In foo, the array of components cannot be empty!")
      end
    end

    context "with a valid configuration" do
      let(:config) { combined_config }

      it "calls validate_config! for all components and does not raise" do
        expect(Entitlements::Data::People::LDAP).to receive(:validate_config!).with("foo:combined_1:LDAP data source 1", ldap_1)
        expect(Entitlements::Data::People::YAML).to receive(:validate_config!).with("foo:combined_1:YAML data source 1", yaml_1)
        expect(Entitlements::Data::People::YAML).to receive(:validate_config!).with("foo:YAML data source 2", yaml_2)
        expect { described_class.validate_config!("foo", config) }.not_to raise_error
      end
    end

    context "with a valid configuration including a string reference" do
      let(:config) do
        {
          "operator" => "or",
          "components" => [
            {
              "type" => "combined",
              "name" => "combined_1",
              "config" => {
                "operator" => "and",
                "components" => ["yaml-1", combined_config["components"][0]["config"]["components"][1]]
              }
            },
            combined_config["components"][1]
          ]
        }
      end

      let(:entitlements_config_hash) do
        {
          "people" => {
            "combined" => {
              "type"   => "combined",
              "config" => {
                "operator"   => "or",
                "components" => [
                  "yaml-1",
                  combined_config["components"][0]["config"]["components"][1]
                ]
              }
            },
            "yaml-1" => combined_config["components"][1]
          }
        }
      end

      it "calls validate_config! for all components and does not raise" do
        expect(Entitlements::Data::People::LDAP).to receive(:validate_config!).with("foo:combined_1:LDAP data source 1", ldap_1)
        expect(Entitlements::Data::People::YAML).to receive(:validate_config!).with("yaml-1", yaml_2)
        expect(Entitlements::Data::People::YAML).to receive(:validate_config!).with("foo:YAML data source 2", yaml_2)
        expect { described_class.validate_config!("foo", config) }.not_to raise_error
      end
    end

    context "with a valid configuration including an invalid string reference" do
      let(:config) do
        {
          "operator" => "or",
          "components" => [
            {
              "type" => "combined",
              "name" => "combined_1",
              "config" => {
                "operator" => "and",
                "components" => ["yaml-fluff", combined_config["components"][0]["config"]["components"][1]]
              }
            },
            combined_config["components"][1]
          ]
        }
      end

      let(:entitlements_config_hash) do
        {
          "people" => {
            "combined" => {
              "type"   => "combined",
              "config" => {
                "operator"   => "or",
                "components" => [
                  "yaml-fluff",
                  combined_config["components"][0]["config"]["components"][1]
                ]
              }
            },
            "yaml-1" => combined_config["components"][1]
          }
        }
      end

      it "raises due to the invalid component reference" do
        expect do
          described_class.validate_config!("foo", config)
        end.to raise_error(ArgumentError, 'In foo:combined_1, reference to invalid component "yaml-fluff"!')
      end
    end
  end

  describe "#read" do
    let(:config) { combined_config }
    let(:subject) { described_class.new_from_config(config) }
    let(:yaml_hash_1) do
      {
        "uid=bob,ou=People,dc=kittens,dc=net" => person_1,
        "uid=tom,ou=People,dc=kittens,dc=net" => person_2
      }
    end
    let(:ldap_hash_1) do
      {
        "uid=bob,ou=People,dc=kittens,dc=net"   => person_2,
        "uid=james,ou=People,dc=kittens,dc=net" => person_3
      }
    end
    let(:yaml_hash_2) do
      {
        "uid=bob,ou=People,dc=kittens,dc=net"    => person_3,
        "uid=paul,ou=People,dc=kittens,dc=net"   => person_2,
        "uid=robert,ou=People,dc=kittens,dc=net" => person_4
      }
    end

    before(:each) do
      allow(Entitlements::Data::People::LDAP).to receive(:new_from_config).with(ldap_1).and_return(ldap_obj_1)
      allow(Entitlements::Data::People::YAML).to receive(:new_from_config).with(yaml_1).and_return(yaml_obj_1)
      allow(Entitlements::Data::People::YAML).to receive(:new_from_config).with(yaml_2).and_return(yaml_obj_2)
      allow(yaml_obj_1).to receive(:read).with(no_args).and_return(yaml_hash_1)
      allow(yaml_obj_2).to receive(:read).with(no_args).and_return(yaml_hash_2)
      allow(ldap_obj_1).to receive(:read).with(no_args).and_return(ldap_hash_1)
    end

    context "reading with no uid" do
      it "returns the hash of username => person object" do
        result = subject.read
        expect(result).to eq(
          "uid=bob,ou=People,dc=kittens,dc=net"    => person_1,
          "uid=paul,ou=People,dc=kittens,dc=net"   => person_2,
          "uid=robert,ou=People,dc=kittens,dc=net" => person_4
        )
      end
    end

    context "reading with a specified uid" do
      it "returns the username's person object" do
        result = subject.read("uid=bob,ou=People,dc=kittens,dc=net")
        expect(result).to eq(person_1)
      end

      it "is case insensitive" do
        result = subject.read("uid=BoB,ou=People,dc=kittens,dc=net")
        expect(result).to eq(person_1)
      end

      it "raises if the username is not found" do
        expect do
          subject.read("uid=james,ou=People,dc=kittens,dc=net")
        end.to raise_error(Entitlements::Data::People::NoSuchPersonError)
      end
    end
  end

  describe "#common_keys" do
    it "returns [] if there are no hashes provided" do
      expect(subject.send(:common_keys, [])).to eq(Set.new)
    end

    it "returns the keys common to all hashes provided" do
      h1 = { "foo" => "bar", "fizz" => "buzz", "bar" => "baz", "kittens" => "awesome" }
      h2 = { "foo" => "foo!", "bar" => "bar!", "kittens" => "awesome", "buzz" => "buzz!" }
      h3 = { "foo" => "foo.", "buzz" => "fizz", "kittens" => "cuddly" }
      expect(subject.send(:common_keys, [h1, h2, h3])).to eq(Set.new(%w[foo kittens]))
    end
  end

  describe "#all_keys" do
    it "returns [] if there are no hashes provided" do
      expect(subject.send(:all_keys, [])).to eq(Set.new)
    end

    it "returns the keys seen in any of the hashes provided" do
      h1 = { "foo" => "bar", "fizz" => "buzz", "bar" => "baz", "kittens" => "awesome" }
      h2 = { "foo" => "foo!", "bar" => "bar!", "kittens" => "awesome", "buzz" => "buzz!" }
      h3 = { "foo" => "foo.", "buzz" => "fizz", "kittens" => "cuddly" }
      expect(subject.send(:all_keys, [h1, h2, h3])).to eq(Set.new(%w[foo fizz bar kittens buzz]))
    end
  end
end
