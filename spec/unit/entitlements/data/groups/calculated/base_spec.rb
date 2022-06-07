# frozen_string_literal: true

require_relative "../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Base do
  before(:each) do
    Entitlements::Extras.load_extra("ldap_group")
    Entitlements::Extras.load_extra("orgchart")
  end

  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj, file_objects: {} } }

  describe "#filtered_members" do
    let(:file) { fixture("ldap-config/filters/contractors-yes-prehires-no.yaml") }
    let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }
    let(:config) { { "base" => "ou=Felines,ou=Groups,dc=kittens,dc=net" } }

    it "removes matching members for filters that are enabled" do
      setup_default_filters
      russianblue = people_obj.read["russianblue"]
      blackmanx = people_obj.read["blackmanx"]

      dummy_prehires = instance_double(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup)
      expect(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup).to receive(:new).and_return(dummy_prehires)
      expect_any_instance_of(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup).not_to receive(:filtered?)
      expect(dummy_prehires).to receive(:filtered?).with(russianblue).and_return(true)
      expect(dummy_prehires).to receive(:filtered?).with(blackmanx).and_return(false)

      dummy_lockout = instance_double(Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup)
      expect(Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup).to receive(:new).and_return(dummy_lockout)
      expect_any_instance_of(Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup).not_to receive(:filtered?)
      expect(dummy_lockout).to receive(:filtered?).with(russianblue).and_return(false)
      expect(dummy_lockout).to receive(:filtered?).with(blackmanx).and_return(false)

      expect(obj.filtered_members).to eq(Set.new([blackmanx]))
    end
  end

  describe "#advanced_filters - included_paths" do
    let(:file) { fixture("ldap-config/filters/included-path-filters.yaml") }
    let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }
    let(:config) { { "base" => "ou=Felines,ou=Groups,dc=kittens,dc=net" } }

    it "file is in included paths, so expect filter checks" do
      included_paths_cfg = {
          class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup,
          config: { "group" => "internal/workday/on-leave", "included_paths" => ["ldap-config/filters"] }
      }
      Entitlements::Data::Groups::Calculated.register_filter("included-paths", included_paths_cfg)
      russianblue = people_obj.read["russianblue"]
      blackmanx = people_obj.read["blackmanx"]

      dummy_included_paths = instance_double(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup)
      expect(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup).to receive(:new).and_return(dummy_included_paths)
      expect_any_instance_of(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup).not_to receive(:filtered?)
      expect(dummy_included_paths).to receive(:filtered?).with(russianblue).and_return(false)
      expect(dummy_included_paths).to receive(:filtered?).with(blackmanx).and_return(false)

      expect(obj.filtered_members).to eq(Set.new([blackmanx, russianblue]))
    end

    it "file is not in included_paths, so no filter checks" do
      included_paths_cfg = {
          class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup,
          config: { "group" => "internal/workday/on-leave", "included_paths" => ["fake-path/is-fake"] }
      }
      Entitlements::Data::Groups::Calculated.register_filter("included-paths", included_paths_cfg)
      russianblue = people_obj.read["russianblue"]
      blackmanx = people_obj.read["blackmanx"]

      expect(obj.filtered_members).to eq(Set.new([blackmanx, russianblue]))
    end
  end

  describe "#advanced_filters - excluded_paths" do
    let(:file) { fixture("ldap-config/filters/excluded-path-filters.yaml") }
    let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }
    let(:config) { { "base" => "ou=Felines,ou=Groups,dc=kittens,dc=net" } }

    it "file is in excluded paths, so expect no filter checks" do
      excluded_paths_cfg = {
          class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup,
          config: { "group" => "internal/workday/on-leave", "excluded_paths" => ["ldap-config/filters"] }
      }
      Entitlements::Data::Groups::Calculated.register_filter("excluded-paths", excluded_paths_cfg)
      russianblue = people_obj.read["russianblue"]
      blackmanx = people_obj.read["blackmanx"]

      expect(obj.filtered_members).to eq(Set.new([blackmanx, russianblue]))
    end

    it "file is not in included_paths, so no filter checks" do
      excluded_paths_cfg = {
          class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup,
          config: { "group" => "internal/workday/on-leave", "excluded_paths" => ["fake-path/is-fake"] }
      }
      Entitlements::Data::Groups::Calculated.register_filter("excluded-paths", excluded_paths_cfg)
      russianblue = people_obj.read["russianblue"]
      blackmanx = people_obj.read["blackmanx"]

      dummy_excluded_paths = instance_double(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup)
      expect(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup).to receive(:new).and_return(dummy_excluded_paths)
      expect_any_instance_of(Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup).not_to receive(:filtered?)
      expect(dummy_excluded_paths).to receive(:filtered?).with(russianblue).and_return(false)
      expect(dummy_excluded_paths).to receive(:filtered?).with(blackmanx).and_return(false)

      expect(obj.filtered_members).to eq(Set.new([blackmanx, russianblue]))
    end
  end

  describe "#modified_members" do
    before(:each) do
      allow_any_instance_of(described_class).to receive(:modifiers_constant).and_return(%w[expiration])
    end

    let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }
    let(:dummy_modifier) { instance_double(Entitlements::Data::Groups::Calculated::Modifiers::Expiration) }
    let(:file) { fixture("ldap-config/expiration/expired-yaml.yaml") }
    let(:config) { { "base" => "ou=Felines,ou=Groups,dc=kittens,dc=net" } }

    it "calls the modifier methods" do
      expect(obj.modified_members).to eq(Set.new)
    end

    it "raises if there is a failure to converge" do
      allow(obj).to receive(:modifiers).and_return("expiration" => "2043-01-01")
      allow(Entitlements::Data::Groups::Calculated::Modifiers::Expiration).to receive(:new).and_return(dummy_modifier)
      expect(dummy_modifier).to receive(:modify).exactly(100).times.and_return(true)
      expect do
        obj.modified_members
      end.to raise_error(RuntimeError, %r{Modifiers for filename=.+/expiration/expired-yaml.yaml failed to converge after 100 iterations})
    end
  end

  describe "#members_from_rules" do
    let(:config) { { "base" => "ou=Felines,ou=Groups,dc=kittens,dc=net" } }

    context "with a complex nested rule set" do
      let(:file) { fixture("ldap-config/logic_tests/nested.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "returns the expected members" do
        result = %w[oJosazuLEs cheetoh cyprus chausie khaomanee mainecoon russianblue napoleon]
        answer_set = Set.new(result.map { |name| people_obj.read["#{name}"] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "with a simple 'and' rule set" do
      let(:file) { fixture("ldap-config/logic_tests/simple_and.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "returns the expected members" do
        result = %w[blackmanx]
        answer_set = Set.new(result.map { |name| people_obj.read["#{name}"] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "with a simple 'or' rule set" do
      let(:file) { fixture("ldap-config/logic_tests/simple_or.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "returns the expected members" do
        result = %w[blackmanx RAGAMUFFIn]
        answer_set = Set.new(result.map { |name| people_obj.read["#{name}"] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "with a simple 'not' rule set" do
      let(:file) { fixture("ldap-config/logic_tests/simple_not.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "returns the expected members" do
        members = obj.members
        expect(members).to be_a_kind_of(Set)
        expect(members).to include(people_obj.read["blackmanx"])
        expect(members).not_to include(people_obj.read["russianblue"])
      end
    end

    context "with a broken 'and' rule set" do
      let(:file) { fixture("ldap-config/logic_tests/busted_and.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "raises the expected error" do
        expect { obj.members }
          .to raise_error(/busted_and.yaml, expected "and" to be a Array but got {"direct_report"=>"MAINECOON"}/)
      end
    end

    context "with a broken 'or' rule set" do
      let(:file) { fixture("ldap-config/logic_tests/busted_or.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "raises the expected error" do
        expect { obj.members }
          .to raise_error(/busted_or.yaml, expected "or" to be a Array but got {"direct_report"=>"MAINECOON"}/)
      end
    end

    context "with a broken 'not' rule set" do
      let(:file) { fixture("ldap-config/logic_tests/busted_not.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "raises the expected error" do
        expect { obj.members }
          .to raise_error(/busted_not.yaml, expected "not" to be a Hash but got \[{"direct_report"=>"MAINECOON"}/)
      end
    end

    context "with no rules" do
      let(:file) { fixture("ldap-config/logic_tests/no_rules.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "raises the expected error" do
        expect { obj.members }
          .to raise_error(/Expected to find 'rules' as a Hash in .+no_rules.yaml/)
      end
    end

    context "with not enough rules" do
      let(:file) { fixture("ldap-config/logic_tests/not_enough_rules.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "raises the expected error" do
        expect { obj.members }
          .to raise_error(/Rule had no keys in .+not_enough_rules.yaml/)
      end
    end

    context "with too many rules" do
      let(:file) { fixture("ldap-config/logic_tests/too_many_rules.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "raises the expected error" do
        expect { obj.members }
          .to raise_error(/Rule Error: Rule had multiple keys .+too_many_rules.yaml/)
      end
    end

    context "with always => false" do
      let(:file) { fixture("ldap-config/logic_tests/always_equals_false.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "returns an empty set" do
        expect(obj.members).to eq(Set.new)
      end
    end

    context "with an alias method in a text file" do
      let(:file) { fixture("ldap-config/text/alias_method.txt") }
      let(:obj) { Entitlements::Data::Groups::Calculated::Text.new(filename: file, config: config) }

      it "returns the expected members" do
        result = %w[russianblue blackmanx]
        answer_set = Set.new(result.map { |name| people_obj.read["#{name}"] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "with an alias method in a YAML file" do
      let(:file) { fixture("ldap-config/logic_tests/alias_method.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "returns the expected members" do
        result = %w[russianblue blackmanx]
        answer_set = Set.new(result.map { |name| people_obj.read["#{name}"] })
        expect(obj.members).to eq(answer_set)
      end
    end

    context "with an unrecognized method" do
      let(:file) { fixture("ldap-config/logic_tests/illegal_method.yaml") }
      let(:obj) { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

      it "raises the expected error" do
        expect { obj.members }
          .to raise_error(/Rule Error: kangaroo is not a valid function .+illegal_method.yaml/)
      end
    end
  end

  describe "#allowed_methods" do
    let(:file) { fixture("ldap-config/logic_tests/nested.yaml") }

    context "with a configuration defining allowed methods" do
      it "returns a Set of allowed methods from the configuration" do
        config = { "allowed_methods" => %w[bogus123 management] }
        subject = Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config)
        expect(subject.send(:allowed_methods)).to eq(Set.new(%w[management]))
      end
    end

    context "with a configuration and invalid allowed methods" do
      it "raises an error" do
        config = { "allowed_methods" => { "foo" => "bar" } }
        subject = Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config)
        expect { subject.send(:allowed_methods) }.to raise_error(ArgumentError, /allowed_methods must be an Array/)
      end
    end

    context "with no configuration" do
      it "returns a Set of allowed methods from the class" do
        config = { "kittens" => "awesome" }
        subject = Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config)
        expect(subject.send(:allowed_methods)).to eq(Set.new(%w[ldap_group direct_report group management username]))
      end
    end
  end

  describe "#function_for" do
    let(:file) { fixture("ldap-config/logic_tests/nested.yaml") }
    let(:config) { { "allowed_methods" => %w[group] } }
    subject { Entitlements::Data::Groups::Calculated::YAML.new(filename: file, config: config) }

    it "returns the underlying function of an alias" do
      expect(subject.send(:function_for, "entitlements_group")).to eq("group")
    end

    it "returns what was entered if it's not an alias" do
      expect(subject.send(:function_for, "group")).to eq("group")
    end
  end
end
