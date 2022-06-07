# frozen_string_literal: true
require_relative "../../spec_helper"
require_relative "../../../../lib/entitlements/models/person"

describe Entitlements::Rule::Base do
  before(:each) do
    setup_default_filters
  end

  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }
  let(:subject) { dummy_class.new }
  let(:subject2) { dummy_class_2.new }
  let(:dummy_class) do
    Class.new(Entitlements::Rule::Base) do
      description "Test Rule"
      filter "contractors" => :all

      def members
        Set.new([
          Entitlements.cache[:people_obj].read("blackmanx"),
          Entitlements.cache[:people_obj].read("russianblue")
        ])
      end
    end
  end

  let(:dummy_class_2) do
    Class.new(Entitlements::Rule::Base) do
      def members
        Set.new([
          Entitlements.cache[:people_obj].read("blackmanx"),
          Entitlements.cache[:people_obj].read("russianblue")
        ])
      end
    end
  end

  describe "#members" do
    it "returns the correct members by filtering people against the `member?` method" do
      answer_array = %w[blackmanx russianblue]
      result_set = Set.new(subject.members.map(&:uid))
      answer_set = Set.new(answer_array)
      expect(result_set).to eq(answer_set)
    end
  end

  describe "#description" do
    it "returns the correct description" do
      expect(subject.description).to eq("Test Rule")
    end

    it "returns the default description when a description is not specified" do
      expect(subject2.description).to eq("")
    end
  end

  describe "#filters" do
    it "returns the correct filters" do
      expect(subject.filters).to eq(default_filters.merge({"contractors"=>:all, "pre-hires"=>:none}))
    end

    it "returns the default filters when filters are not specified" do
      expect(subject2.filters).to eq(default_filters.merge({"contractors"=>:none, "pre-hires"=>:none}))
    end
  end
end
