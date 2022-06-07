# frozen_string_literal: true

require_relative "../../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Rules::Group do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj, file_objects: {} } }

  describe "#matches" do
    context "for a circular dependency" do
      let(:file) { fixture("ldap-config/circular_dependency/group1.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

      it "raises an error due to circular dependency" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("circular_dependency")
          .and_return(fixture("ldap-config/circular_dependency"))
        message = "Error: Circular dependency circular_dependency/group1 -> circular_dependency/group2 -> circular_dependency/group3 -> circular_dependency/group1"
        expect { obj.members }.to raise_error(message)
      end
    end

    context "for a circular dependency starting at another point" do
      let(:file) { fixture("ldap-config/circular_dependency/group2.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

      it "raises an error due to circular dependency" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("circular_dependency")
          .and_return(fixture("ldap-config/circular_dependency"))
        message = "Error: Circular dependency circular_dependency/group2 -> circular_dependency/group3 -> circular_dependency/group1 -> circular_dependency/group2"
        expect { obj.members }.to raise_error(message)
      end
    end

    context "for a circular dependency due to a self-referencing group" do
      let(:file) { fixture("ldap-config/circular_dependency/group4.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

      it "raises an error due to circular dependency" do
        Entitlements.config_file = fixture("config.yaml")
        message = "Error: Circular dependency circular_dependency/group4 -> circular_dependency/group4"
        expect { obj.members }.to raise_error(message)
      end
    end

    context "for a circular dependency that starts deeper in the tree" do
      let(:file) { fixture("ldap-config/circular_dependency_2/group1.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

      it "raises an error due to circular dependency" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("circular_dependency_2")
          .and_return(fixture("ldap-config/circular_dependency_2"))
        message = "Error: Circular dependency circular_dependency_2/group1 -> circular_dependency_2/group3 -> circular_dependency_2/group4 -> circular_dependency_2/group6 -> circular_dependency_2/group3"
        expect { obj.members }.to raise_error(message)
      end
    end

    context "for a referenced file with an unrecognized extension" do
      let(:file) { fixture("ldap-config/missing_references/group1.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

      it "raises an error due to missing file" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("missing_references")
          .and_return(fixture("ldap-config/missing_references"))
        expect do
          obj.members
        end.to raise_error(%r{Error: Could not find a configuration for .+/group2.\(rb\|txt\|yaml\) \(filename: ".+/group1.yaml"\)})
      end
    end

    context "for a referenced file that simply does not exist" do
      let(:file) { fixture("ldap-config/missing_references/group3.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

      it "raises an error due to missing file" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("missing_references")
          .and_return(fixture("ldap-config/missing_references"))
        expect { obj.members }.to raise_error(%r{Error: Could not find a configuration for .+/group4.\(rb\|txt\|yaml\)})
      end
    end

    context "for a nested dependency graph that is valid" do
      let(:file) { fixture("ldap-config/nested_groups/group1.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file) }

      it "returns the members" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("nested_groups")
          .and_return(fixture("ldap-config/nested_groups"))
        result = %w[blackmanx RAGAMUFFIn foldex]
        answer_set = Set.new(result.map { |name| people_obj.read[name] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "for a wildcard group that does not self-reference" do
      let(:file) { fixture("ldap-config/wildcard_1/bar.txt") }
      let(:obj) { Entitlements::Data::Groups::Calculated::Text.new(filename: file) }

      it "returns the members" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("wildcard_1")
          .and_return(fixture("ldap-config/wildcard_1"))
        result = %w[blackmanx RAGAMUFFIn]
        answer_set = Set.new(result.map { |name| people_obj.read[name] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "for a wildcard group that self-references" do
      let(:file) { fixture("ldap-config/wildcard_1/self.txt") }
      let(:obj) { Entitlements::Data::Groups::Calculated::Text.new(filename: file) }

      it "returns the members" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("wildcard_1")
          .and_return(fixture("ldap-config/wildcard_1"))
        result = %w[blackmanx RAGAMUFFIn mainecoon]
        answer_set = Set.new(result.map { |name| people_obj.read[name] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "for a group that self-references" do
      let(:file) { fixture("ldap-config/circular_dependency/circular.txt") }
      let(:obj) { Entitlements::Data::Groups::Calculated::Text.new(filename: file) }

      it "raises an error due to circular dependencies" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("circular_dependency")
          .and_return(fixture("ldap-config/circular_dependency"))
        message = "Error: Invalid self-referencing wildcard in circular_dependency/circular.txt"
        expect { obj.members }.to raise_error(message)
      end
    end

    context "for a group with a multi-level reference" do
      let(:file) { fixture("ldap-config/multi_level/test.txt") }
      let(:obj) { Entitlements::Data::Groups::Calculated::Text.new(filename: file) }

      it "returns the members" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with("multi_level/child_ou")
          .and_return(fixture("ldap-config/multi_level/child_ou"))
        result = %w[blackmanx mainecoon]
        answer_set = Set.new(result.map { |name| people_obj.read[name] })
        expect(obj.members).to eq(answer_set)
      end
    end
  end

  describe "#files_for" do
    after(:each) do
      described_class.instance_variable_set(:"@files_for_cache", nil)
    end

    it "returns {} when directory does not exist and skip_broken_references is set" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("foo").and_return("/bar/foo")
      expect(File).to receive(:directory?).with("/bar/foo").and_return(false)
      allow(File).to receive(:directory?).and_call_original
      expect(logger).to receive(:warn).with("Could not find any configuration in /bar/foo - skipped")

      result = described_class.files_for("foo", options: {skip_broken_references: true})
      expect(result).to eq({})
    end

    it "raises an error when directory does not exist and skip_broken_references is not set" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("foo").and_return("/bar/foo")
      expect(File).to receive(:directory?).with("/bar/foo").and_return(false)
      allow(File).to receive(:directory?).and_call_original
      expect(logger).to receive(:fatal).with("Error: Could not find any configuration in /bar/foo")
      expect do
        described_class.files_for("foo", options: {})
      end.to raise_error(RuntimeError, "Error: Could not find any configuration in /bar/foo")
    end

    it "returns a hash of {file_without_extension => extension}" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("foo").and_return("/bar/foo")
      expect(File).to receive(:directory?).with("/bar/foo").and_return(true)
      allow(File).to receive(:directory?).and_call_original
      expect(Dir).to receive(:entries).with("/bar/foo").and_return(%w[. .. fizzbuzz.txt foobar.md subdir.txt ruby.rb yaml.yaml])
      expect(File).to receive(:file?).with("/bar/foo/fizzbuzz.txt").and_return(true)
      expect(File).to receive(:file?).with("/bar/foo/ruby.rb").and_return(true)
      expect(File).to receive(:file?).with("/bar/foo/subdir.txt").and_return(false)
      expect(File).to receive(:file?).with("/bar/foo/yaml.yaml").and_return(true)
      expect(File).not_to receive(:file?).with("/bar/foo/foobar.md")
      allow(File).to receive(:fil?).and_call_original

      result = described_class.files_for("foo", options: {})
      expect(result).to eq("fizzbuzz" => "txt", "ruby" => "rb", "yaml" => "yaml")
    end
  end
end
