# frozen_string_literal: true
require_relative "../../spec_helper"

describe Entitlements::Auditor::Base do
  class Entitlements::Auditor::BaseTestDummy < Entitlements::Auditor::Base; end

  let(:stringio) { StringIO.new }
  let(:logger) { Logger.new(stringio) }

  describe "#description" do
    it "returns the provided description" do
      subject = Entitlements::Auditor::BaseTestDummy.new(logger, {"description" => "Fluffy Kittens", "foo" => "bar"})
      expect(subject.description).to eq("Fluffy Kittens")
    end

    it "returns the class name by default" do
      subject = Entitlements::Auditor::BaseTestDummy.new(logger, {"foo" => "bar"})
      expect(subject.description).to eq("Entitlements::Auditor::BaseTestDummy")
    end
  end

  describe "#provider_id" do
    it "returns the provided provider ID" do
      subject = Entitlements::Auditor::BaseTestDummy.new(logger, {"provider_id" => "FluffyKittens", "foo" => "bar"})
      expect(subject.provider_id).to eq("FluffyKittens")
    end

    it "returns the short class name by default" do
      subject = Entitlements::Auditor::BaseTestDummy.new(logger, {"foo" => "bar"})
      expect(subject.provider_id).to eq("BaseTestDummy")
    end
  end

  describe "#log" do
    it "logs a message with the class name when the provider ID is not special" do
      logger = instance_double(Logger)
      subject = Entitlements::Auditor::BaseTestDummy.new(logger, {"provider_id" => "FluffyKittens"})

      expect(logger).to receive(:debug)
        .with("Entitlements::Auditor::BaseTestDummy[FluffyKittens]: Hello there")

      instance_logger = subject.send(:logger)
      instance_logger.debug "Hello there"
    end

    it "logs a message with the class name and provider ID" do
      logger = instance_double(Logger)
      subject = Entitlements::Auditor::BaseTestDummy.new(logger, {})

      expect(logger).to receive(:fatal)
        .with("Entitlements::Auditor::BaseTestDummy: Good day")

      instance_logger = subject.send(:logger)
      instance_logger.fatal "Good day"
    end
  end

  describe "#configuration_error" do
    it "logs and raises" do
      logger = instance_double(Logger)
      subject = Entitlements::Auditor::BaseTestDummy.new(logger, {"provider_id" => "FluffyKittens"})

      expect(logger).to receive(:fatal)
        .with("Entitlements::Auditor::BaseTestDummy[FluffyKittens]: Configuration error: XYZ")

      expect do
        subject.send(:configuration_error, "XYZ")
      end.to raise_error(ArgumentError, "Configuration error for provider=BaseTestDummy id=FluffyKittens: XYZ")
    end
  end

  describe "#require_config_keys" do
    let(:subject) { Entitlements::Auditor::BaseTestDummy.new(logger, {"foo" => "bar", "fizz" => "buzz", "baz" => "bizz"}) }

    it "raises if config keys are missing" do
      expect(subject).to receive(:configuration_error).with("Not all required keys are defined. Missing: bar,buzz.")
      subject.send(:require_config_keys, %w[foo bar baz buzz])
    end

    it "returns if config keys are present" do
      expect(subject).not_to receive(:configuration_error)
      subject.send(:require_config_keys, %w[foo fizz])
    end
  end

  describe "#path_from_dn" do
    let(:subject) { Entitlements::Auditor::BaseTestDummy.new(logger, {"foo" => "bar", "fizz" => "buzz", "baz" => "bizz"}) }

    it "creates the correct path from the DN" do
      dn = "cn=russian-blues,ou=kittens,dc=example,dc=net"
      path = "dc=net/dc=example/ou=kittens/cn=russian-blues"
      expect(subject.send(:path_from_dn, dn)).to eq(path)
    end
  end

  describe "#dn_from_path" do
    let(:subject) { Entitlements::Auditor::BaseTestDummy.new(logger, {"foo" => "bar", "fizz" => "buzz", "baz" => "bizz"}) }

    it "creates the correct DN from the path" do
      dn = "cn=russian-blues,ou=kittens,dc=example,dc=net"
      path = "/dc=net/dc=example//ou=kittens/cn=russian-blues"
      expect(subject.send(:dn_from_path, path)).to eq(dn)
    end
  end

  describe "#actions_with_membership_change" do
    let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }

    let(:dn) { "cn=group1,ou=kittens,dc=example,dc=net" }
    let(:ou) { "kittens" }

    let(:user1) { people_obj.read("blackmanx") }
    let(:user2) { people_obj.read("russianblue") }
    let(:user3) { people_obj.read("nebelung") }

    let(:member_set_1) { Set.new([user1, user2]) }
    let(:member_set_2) { Set.new([user2, user3]) }

    let(:group1) { Entitlements::Models::Group.new(dn: dn, members: member_set_1, description: "Group 1") }
    let(:group1d) { Entitlements::Models::Group.new(dn: dn, members: member_set_1, description: "Group 1 new description") }
    let(:group1m) { Entitlements::Models::Group.new(dn: dn, members: member_set_2, description: "Group 1") }

    let(:action_add) { Entitlements::Models::Action.new(dn, nil, group1, ou) }
    let(:action_del) { Entitlements::Models::Action.new(dn, group1, nil, ou) }
    let(:action_change) { Entitlements::Models::Action.new(dn, group1, group1m, ou) }
    let(:action_change_description) { Entitlements::Models::Action.new(dn, group1, group1d, ou) }
    let(:action_person) { Entitlements::Models::Action.new(dn, :none, user1, ou) }

    let(:subject) { Entitlements::Auditor::BaseTestDummy.new(logger, {"foo" => "bar", "fizz" => "buzz", "baz" => "bizz"}) }

    it "filters out the action where group membership is the same" do
      result = subject.send(:actions_with_membership_change, [action_add, action_del, action_change, action_change_description, action_person])
      expect(result).to eq([action_add, action_del, action_change])
    end
  end
end
