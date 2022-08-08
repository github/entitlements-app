# frozen_string_literal: true
require_relative "../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Ruby do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }
  let(:subject) { described_class.new(filename: filename) }

  before(:each) do
    setup_default_filters
  end

  describe "#members" do
    let(:dummy_rule_obj) { double }
    let(:filename) { fixture("ldap-config/filters/no-filters.rb") }

    it "raises an error if result is not a set" do
      members = {}
      allow(subject).to receive(:rule_obj).and_return(dummy_rule_obj)
      allow(dummy_rule_obj).to receive(:members).and_return(members)
      message = "Expected Set[String|Entitlements::Models::Person] from Entitlements::Rule::Filters::NoFilters.members, got Hash!"
      expect { subject.members }.to raise_error(RuntimeError, message)
    end

    it "raises an error if any element of the set is not a string or a person" do
      person = Entitlements::Models::Person.new(uid: "foo")
      members = Set.new(["abc", person, :ghi])
      people_read = { "abc" => nil }
      allow(subject).to receive(:rule_obj).and_return(dummy_rule_obj)
      allow(dummy_rule_obj).to receive(:members).and_return(members)
      allow(people_obj).to receive(:read).and_return(people_read)
      message = "In Entitlements::Rule::Filters::NoFilters.members, expected String or Person but got :ghi"
      expect { subject.members }.to raise_error(RuntimeError, message)
    end

    it "returns the set it received" do
      person_abc = Entitlements::Models::Person.new(uid: "abc")
      person_foo = Entitlements::Models::Person.new(uid: "foo")
      members_in = Set.new(["abc", person_foo])
      members_out = Set.new([person_abc, person_foo])
      people_read = { person_abc.uid => person_abc, person_foo.uid => person_foo }
      allow(subject).to receive(:rule_obj).and_return(dummy_rule_obj)
      allow(dummy_rule_obj).to receive(:members).and_return(members_in)
      allow(people_obj).to receive(:read).and_return(people_read)
      expect(subject.members).to eq(members_out)
    end
  end

  describe "#description" do
    let(:dummy_rule_obj) { double }
    let(:filename) { fixture("ldap-config/filters/no-filters.rb") }

    it "returns the string when one is set" do
      allow(subject).to receive(:rule_obj).and_return(dummy_rule_obj)
      allow(dummy_rule_obj).to receive(:description).and_return("Yo kittens")
      expect(subject.description).to eq("Yo kittens")
    end

    it "raises an error when description is not a string" do
      allow(subject).to receive(:rule_obj).and_return(dummy_rule_obj)
      allow(dummy_rule_obj).to receive(:description).and_return([{foo: nil}])
      message = "Expected String from Entitlements::Rule::Filters::NoFilters.description, got Array!"
      expect { subject.description }.to raise_error(RuntimeError, message)
    end
  end

  describe "#filters" do
    it "returns the default hash if there are no filters defined" do
      filename = fixture("ldap-config/filters/no-filters.rb")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors"=>:none, "pre-hires"=>:none))
    end

    it "returns the default hash with overrides from one defined filter" do
      filename = fixture("ldap-config/filters/one-filter.rb")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors"=>:all, "pre-hires"=>:none))
    end

    it "returns the default hash with overrides from two filters defined at the same time" do
      filename = fixture("ldap-config/filters/two-filters-one-statement.rb")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors"=>:all, "pre-hires"=>:all))
    end

    it "returns the default hash with overrides from two filters defined in different statements" do
      filename = fixture("ldap-config/filters/two-filters-two-statements.rb")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors"=>:all, "pre-hires"=>:all))
    end

    it "handles a single string in the filter" do
      filename = fixture("ldap-config/filters/one-filter-value.rb")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors"=>%w[kittens], "pre-hires"=>:none))
    end

    it "handles an array of strings in the filter" do
      filename = fixture("ldap-config/filters/multiple-contractors-1.rb")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors"=>["pixiEBOB", "SErengeti"], "pre-hires"=>:none))
    end

    it "raises an error when an unexpected data structure is created" do
      filename = fixture("ldap-config/filters/filter-bad-data-structure.rb")
      if Entitlements.ruby_version2?
        expect { described_class.new(filename: filename) }.to raise_error(ParamContractError)
      else
        expect { described_class.new(filename: filename) }.to raise_error(ReturnContractError)
      end
    end
  end

  describe "#initialize_metadata" do
    it "returns an empty hash if there is no metadata method" do
      filename = fixture("ldap-config/metadata/undefined.rb")
      expect(described_class.new(filename: filename).metadata).to eq({})
    end

    it "raises an error if metadata is not a hash" do
      filename = fixture("ldap-config/metadata/bad-data-structure.rb")
      message = "For metadata in #{filename}: expected Hash, got :kittens!"
      expect { described_class.new(filename: filename) }.to raise_error(message)
    end

    it "raises an error if a key in the metadata is not a string" do
      filename = fixture("ldap-config/metadata/bad-data-key.rb")
      message = "For metadata in #{filename}: keys are expected to be strings, but :kittens is not!"
      expect { described_class.new(filename: filename) }.to raise_error(message)
    end

    it "returns the hash of metadata" do
      filename = fixture("ldap-config/metadata/good.rb")
      subject = described_class.new(filename: filename)
      expect(subject.metadata).to eq("kittens" => "awesome", "puppies" => "young dogs")
    end
  end

  describe "#raise_rule_exception" do
    it "raises with the reference to the offending class and filename" do
      filename = fixture("ldap-config/ruby/raiser.rb")
      expect(logger).to receive(:fatal).with("KeyError when processing Entitlements::Rule::Ruby::Raiser!")

      subject = described_class.new(filename: filename)
      expect { subject.members }.to raise_error(KeyError, 'key not found: "abc"')
    end
  end

  describe "#ruby_class_name" do
    let(:filename) { fixture("ldap-config/filters/no-filters.rb") }

    it "returns the correct class name based on the filename" do
      expect(subject.send(:ruby_class_name)).to eq("Entitlements::Rule::Filters::NoFilters")
    end
  end
end
