# frozen_string_literal: true
require_relative "../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::YAML do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }

  before(:each) do
    setup_default_filters
  end

  describe "#members" do
    it "returns the expected member list" do
      filename = fixture("ldap-config/filters/no-filters.yaml")
      subject = described_class.new(filename: filename)
      result = subject.members
      answer = %w[blackmanx russianblue]
      expect(result).to be_a_kind_of(Set)
      expect(result.size).to eq(2)
      expect(result.map { |i| i.uid }.sort).to eq(answer)
    end
  end

  describe "#description" do
    it "returns the string when one is set" do
      filename = fixture("ldap-config/filters/no-filters.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.description).to eq("Yo kittens")
    end

    it "returns an empty-string when description is undefined" do
      filename = fixture("ldap-config/filters/no-filters-description.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.description).to eq("")
    end
  end

  describe "#schema_version" do
    it "returns the version string when one is set" do
      filename = fixture("ldap-config/filters/no-filters-with-schema-version.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.schema_version).to eq("entitlements/1.2.3")
    end

    it "returns the version string when one is set without the patch" do
      filename = fixture("ldap-config/filters/no-filters-with-schema-version-no-patch.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.schema_version).to eq("entitlements/1.2")
    end

    it "returns the version string when one is set (with v prefix)" do
      filename = fixture("ldap-config/filters/no-filters-with-schema-version-with-v.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.schema_version).to eq("entitlements/v1.2.3")
    end

    it "returns the default version when schema_version is undefined" do
      filename = fixture("ldap-config/filters/no-filters-description.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.schema_version).to eq("entitlements/v1")
    end

    it "throws an error when an invalid schema_version string is provided" do
      filename = fixture("ldap-config/filters/no-filters-with-bad-schema-version.yaml")
      subject = described_class.new(filename: filename)
      expect { subject.schema_version }.to raise_error(RuntimeError, /Invalid schema version format/)
    end

    it "throws an error when the version string is missing the namespace" do
      filename = fixture("ldap-config/filters/no-filters-with-missing-version-namespace.yaml")
      subject = described_class.new(filename: filename)
      expect { subject.schema_version }.to raise_error(RuntimeError, /Invalid schema version format/)
    end
  end

  describe "#initialize_filters" do
    it "returns the default filter hash when no filters are defined" do
      filename = fixture("ldap-config/filters/no-filters.yaml")
      subject = described_class.new(filename: filename)
      answer = default_filters
      expect(subject.filters).to eq(answer)
    end

    it "returns the correct filter when one key is defined" do
      filename = fixture("ldap-config/filters/one-filter.yaml")
      subject = described_class.new(filename: filename)
      answer = default_filters.merge("contractors" => :all)
      expect(subject.filters).to eq(answer)
    end

    it "returns the correct filter when two keys are defined" do
      filename = fixture("ldap-config/filters/two-filters.yaml")
      subject = described_class.new(filename: filename)
      answer = default_filters.merge("contractors" => :all, "pre-hires" => :all)
      expect(subject.filters).to eq(answer)
    end

    it "raises an error when filters is not a hash" do
      filename = fixture("ldap-config/filters/bad-data-structure.yaml")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/For filters in .+\/bad-data-structure.yaml: expected Hash, got "kittens"!/)
    end

    it "raises an error for an invalid key" do
      filename = fixture("ldap-config/filters/one-filter-invalid-key.yaml")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/Filter kittens in .+\/one-filter-invalid-key.yaml is invalid!/)
    end

    it "sets contractors filter to an array when specified in file" do
      filename = fixture("ldap-config/filters/multiple-contractors-1.yaml")
      subject = described_class.new(filename: filename)
      answer = default_filters.merge("contractors" => %w[pixiEBOB SErengeti], "pre-hires" => :none)
      expect(subject.filters).to eq(answer)
    end

    it "returns an array with a single entry for a non-keyword" do
      filename = fixture("ldap-config/filters/one-filter-value.yaml")
      subject = described_class.new(filename: filename)
      answer = default_filters.merge("contractors" => ["kittens"], "pre-hires" => :none)
      expect(subject.filters).to eq(answer)
    end

    it "raises an error when the key of a filter is repeated" do
      filename = fixture("ldap-config/filters/one-filter-repeated.yaml")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/In .+\/one-filter-repeated.yaml, contractors cannot contain multiple entries when 'all' or 'none' is used!/)
    end

    it "raises an error when an unexpected data structure is created" do
      filename = fixture("ldap-config/filters/filter-bad-data-structure.yaml")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/Value {"foo"=>"bar", "fizz"=>"buzz"} for contractors/)
    end

    it "treats an expired contractor filter as not even being present" do
      filename = fixture("ldap-config/filters/expiration-contractor-expired.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters)
    end

    it "treats a non-expired contractor filter normally" do
      filename = fixture("ldap-config/filters/expiration-contractor-nonexpired.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors" => %w[pixiebob]))
    end

    it "removes expired contractor filters and keeps non-expired ones" do
      filename = fixture("ldap-config/filters/expiration-contractor-mixedexpired.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors" => %w[pixiebob]))
    end

    it "handles a filter specified with a key but no other settings" do
      filename = fixture("ldap-config/filters/expiration-contractor-onlykey.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors" => %w[pixiebob serengeti]))
    end
  end

  describe "#initialize_metadata" do
    it "returns an empty hash if there is no metadata key" do
      filename = fixture("ldap-config/metadata/undefined.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.metadata).to eq({})
    end

    it "raises an error if metadata is not a hash" do
      filename = fixture("ldap-config/metadata/bad-data-structure.yaml")
      message = "For metadata in #{filename}: expected Hash, got [\"kittens=awesome\", \"puppies=young dogs\"]!"
      expect do
        described_class.new(filename: filename)
      end.to raise_error(message)
    end

    it "raises an error if a key in the metadata is not a string" do
      filename = fixture("ldap-config/metadata/bad-data-key.yaml")
      message = "For metadata in #{filename}: keys are expected to be strings, but 12345 is not!"
      expect do
        described_class.new(filename: filename)
      end.to raise_error(message)
    end

    it "returns the hash of metadata" do
      filename = fixture("ldap-config/metadata/good.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.metadata).to eq("kittens" => "awesome", "puppies" => "young dogs")
    end
  end

  describe "#modifiers" do
    it "returns an empty hash if there are no modifiers" do
      filename = fixture("ldap-config/metadata/undefined.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.modifiers).to eq({})
    end

    it "returns a hash of the modifiers" do
      filename = fixture("ldap-config/expiration/valid-yaml-quoted-date.yaml")
      subject = described_class.new(filename: filename)
      expect(subject.modifiers).to eq("expiration"=>"2043-01-01")
    end
  end

  describe "#rules" do
    let(:subject) { described_class.new(filename: filename) }

    context "with expiration" do
      context "not expired" do
        let(:filename) { fixture("ldap-config/yaml/expiration-not-expired.yaml") }

        it "constructs the correct rule set" do
          answer = {
            "or" => [
              { "username" => "blackmanx" },
              { "username" => "russianblue" },
              { "username" => "mainecoon" }
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "already expired" do
        let(:filename) { fixture("ldap-config/yaml/expiration-already-expired.yaml") }

        it "constructs the correct rule set" do
          answer = {
            "or" => [
              { "username" => "mainecoon" }
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "mix of not expired and already expired" do
        let(:filename) { fixture("ldap-config/yaml/expiration-mixed-expired.yaml") }

        it "constructs the correct rule set" do
          answer = {
            "or" => [
              { "username" => "blackmanx" },
              { "username" => "mainecoon" }
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "all rules expired" do
        let(:filename) { fixture("ldap-config/yaml/expiration-all-expired.yaml") }

        it "constructs the correct rule set" do
          answer = {
            "or" => []
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "complex structure" do
        let(:filename) { fixture("ldap-config/yaml/expiration-complex.yaml") }

        it "constructs the correct rule set" do
          answer = {
            "or"=>[
              {"username"=>"peterbald"},
              {"and"=>[{"group"=>"foo/bar"}]},
              {"or"=>[]},
              {"or"=>[{"username"=>"nebelung"}]}
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end
    end
  end
end
