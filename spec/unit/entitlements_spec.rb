# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  let(:subject) { Entitlements }

  describe "#config" do
    before(:each) do
      ENV["TEST_ERB_VARIABLE"] = "Hello, ERB world!"
    end

    after(:each) do
      ENV.delete("TEST_ERB_VARIABLE")
    end

    it "returns parsed YAML of the configuration file" do
      subject.config_file = fixture("config.yaml")
      expect(subject.config["configuration_path"]).to eq("./ldap-config")
    end

    it "returns parsed YAML with ERB substitutions" do
      subject.config_file = fixture("config_with_erb.yaml")
      expect(subject.config["kittens"]).to eq("Hello, ERB world!")
    end
  end

  describe "#config_file=" do
    it "raises an error when the specified path does not exist" do
      expect { subject.config_file = fixture("non-existing.yaml") }.to raise_error(/does not exist!\z/)
    end
  end

  describe "#config_path=" do
    it "raises an error when the given path is not absolute" do
      expect do
        subject.config_path = "foo"
      end.to raise_error(ArgumentError, "Path must be absolute when setting config_path!")
    end

    it "raises an error when the given path does not exist as a directory" do
      expect do
        subject.config_path = fixture("non-existing")
      end.to raise_error(Errno::ENOENT, %r{No such file or directory - config_path ".+fixtures/non-existing" is not a directory!})
    end

    it "sets the 'configuration_path' config key and returns the path" do
      expect(subject.config_path = fixture("config-files")).to eq(fixture("config-files"))
    end
  end

  describe "#load_extras" do
    context "with extras undefined" do
      let(:entitlements_config_hash) { {} }

      it "does nothing" do
        expect(Entitlements).not_to receive(:load_extra)
        expect(described_class.load_extras).to be nil
      end
    end

    context "with extras defined" do
      let(:entitlements_config_hash) do
        {
          "extras" => {
            "bar_extra" => {},
            "foo_extra" => { "path" => "/foo/extra" }
          }
        }
      end

      let(:class1) { Class }
      let(:class2) { Class }

      it "loads the methods from the defined paths" do
        expect(Entitlements::Extras).to receive(:load_extra).with("foo_extra", "/foo/extra").and_return(class1)
        expect(Entitlements::Extras).to receive(:load_extra).with("bar_extra", nil).and_return(class2)
        expect(logger).to receive(:debug).with("Loading extra bar_extra (path = default)")
        expect(logger).to receive(:debug).with("Loading extra foo_extra (path = /foo/extra)")
        expect(described_class.load_extras).to be nil
      end
    end
  end

  describe "#register_filters" do
    before(:each) do
      Entitlements::Extras.load_extra("ldap_group")
    end

    let(:entitlements_config_hash) do
      {
        "filters" => {
          "filter1" => {
            "class"  => "Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup",
            "config" => { "foo" => "bar" }
          },
          "filter2" => { "class" => "Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup" }
        }
      }
    end

    it "calls Entitlements::Data::Groups::Calculated with appropriate arguments" do
      expect(Entitlements::Data::Groups::Calculated).to receive(:register_filter)
        .with("filter1", class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup, config: { "foo" => "bar" })
      expect(Entitlements::Data::Groups::Calculated).to receive(:register_filter)
        .with("filter2", class: Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup, config: {})
      expect(logger).to receive(:debug).with("Registering filter filter1 (class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup)")
      expect(logger).to receive(:debug).with("Registering filter filter2 (class: Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup)")
      described_class.register_filters
    end
  end

  describe "#auditors" do
    before(:each) do
      described_class.instance_variable_set("@auditors", nil)
    end

    context "with no auditors defined" do
      let(:entitlements_config_hash) { {} }

      it "returns an empty array" do
        expect(described_class.auditors).to eq([])
      end
    end

    context "with auditors defined" do
      let(:auditor1_cfg) { { "auditor_class" => "Base", "foo" => "bar" } }
      let(:auditor1) { Entitlements::Auditor::Base.new(logger, auditor1_cfg) }
      let(:auditor2_cfg) { { "auditor_class" => "Base", "foo" => "bar" } }
      let(:auditor2) { Entitlements::Auditor::Base.new(logger, auditor2_cfg) }
      let(:entitlements_config_hash) { { "auditors" => [auditor1_cfg, auditor2_cfg] } }

      it "returns an array of auditor objects" do
        allow(Entitlements::Auditor::Base).to receive(:new).with(logger, auditor1_cfg).and_return(auditor1)
        allow(Entitlements::Auditor::Base).to receive(:new).with(logger, auditor2_cfg).and_return(auditor2)
        expect(described_class.auditors).to eq([auditor1, auditor2])
      end
    end

    context "when an auditor object cannot be found" do
      let(:auditor1_cfg) { { "auditor_class" => "FooBarBazBuzzChicken", "foo" => "bar" } }
      let(:entitlements_config_hash) { { "auditors" => [auditor1_cfg] } }

      it "raises" do
        expect { described_class.auditors }.to raise_error(ArgumentError, 'Auditor class "FooBarBazBuzzChicken" is invalid')
      end
    end
  end

  describe "#child_classes" do
    context "with a file with multiple backend types" do
      let(:entitlements_config_file) { fixture("config-files/class-order.yaml") }

      it "has child classes in the correct order per priorities" do
        expect(described_class.child_classes.keys).to eq([
          "pizza_teams",
          "pizza_teams_mirror",
          "member_of"
        ])
      end
    end

    context "with a dummy backend" do
      let(:entitlements_config_file) { fixture("config-files/valid.yaml") }

      it "raises through an error from a child class" do
        exc = RuntimeError.new("Boom")
        expect_any_instance_of(Entitlements::Backend::Dummy::Controller).to receive(:validate_config!).and_raise(exc)
        expect { described_class.child_classes }.to raise_error(RuntimeError, "Boom")
      end
    end
  end

  describe "#calculate" do
    let(:cache) { { people_obj: people_ldap } }
    let(:action1) { instance_double(Entitlements::Models::Action) }
    let(:action2) { instance_double(Entitlements::Models::Action) }
    let(:actions) { [action1, action2] }
    let(:people_ldap) { instance_double(Entitlements::Data::People::LDAP) }
    let(:ldap_controller) { instance_double(Entitlements::Backend::LDAP::Controller) }
    let(:other_controller) { instance_double(Entitlements::Backend::LDAP::Controller) }

    it "returns the list of actions and updates the change count" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)

      allow(ldap_controller).to receive(:prefetch).with(no_args)
      allow(ldap_controller).to receive(:validate).with(no_args)
      allow(ldap_controller).to receive(:calculate).with(no_args)
      allow(ldap_controller).to receive(:change_count).and_return(2)
      allow(ldap_controller).to receive(:actions).and_return([action1])

      allow(other_controller).to receive(:prefetch).with(no_args)
      allow(other_controller).to receive(:validate).with(no_args)
      allow(other_controller).to receive(:calculate).with(no_args)
      allow(other_controller).to receive(:change_count).and_return(1)
      allow(other_controller).to receive(:actions).and_return([action2])

      expect(Entitlements).to receive(:prefetch_people)

      returned_actions = described_class.calculate
      expect(returned_actions).to eq(actions)

      expect(cache[:change_count]).to eq(3)
    end
  end

  describe "#execute" do
    let(:cache) { { people_obj: people_ldap } }
    let(:people_ldap) { instance_double(Entitlements::Data::People::LDAP) }

    let(:auditor1) { instance_double(Entitlements::Auditor::Base) }
    let(:auditor2) { instance_double(Entitlements::Auditor::Base) }

    let(:action1) { instance_double(Entitlements::Models::Action) }
    let(:action2) { instance_double(Entitlements::Models::Action) }
    let(:actions) { [action1, action2] }

    let(:exc) { RuntimeError.new("Boom") }
    let(:exc2) { RuntimeError.new("Boom Boom") }

    let(:ldap_controller) { instance_double(Entitlements::Backend::LDAP::Controller) }
    let(:other_controller) { instance_double(Entitlements::Backend::LDAP::Controller) }

    let(:entitlements_config_file) { fixture("config-files/entitlements-execute.yaml") }

    it "returns without error if providers and auditors work" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)
      allow(Entitlements).to receive(:auditors).and_return([auditor1, auditor2])

      allow(ldap_controller).to receive(:preapply)
      allow(other_controller).to receive(:preapply)

      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action1).to receive(:ou).and_return("ldap-dir")
      allow(action2).to receive(:dn).and_return("cn=action2")
      allow(action2).to receive(:ou).and_return("other-ldap-dir")
      allow(ldap_controller).to receive(:apply).with(action1)
      allow(other_controller).to receive(:apply).with(action2)

      expect(auditor1).to receive(:setup)
      expect(auditor1).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn, action2.dn]),
          provider_exception: nil
        )
      expect(auditor1).to receive(:description).and_return("Auditor 1")

      expect(auditor2).to receive(:setup)
      expect(auditor2).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn, action2.dn]),
          provider_exception: nil
        )
      expect(auditor2).to receive(:description).and_return("Auditor 2")

      expect(logger).to receive(:debug).with("Recording data to 2 audit provider(s)")
      expect(logger).to receive(:debug).with("Audit Auditor 1 completed successfully")
      expect(logger).to receive(:debug).with("Audit Auditor 2 completed successfully")

      expect { described_class.execute(actions: actions) }.not_to raise_error
    end

    it "returns without error with no auditors configured" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)
      allow(Entitlements).to receive(:auditors).and_return([])

      allow(ldap_controller).to receive(:preapply)
      allow(other_controller).to receive(:preapply)

      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action1).to receive(:ou).and_return("ldap-dir")
      allow(action2).to receive(:dn).and_return("cn=action2")
      allow(action2).to receive(:ou).and_return("other-ldap-dir")
      allow(ldap_controller).to receive(:apply).with(action1)
      allow(other_controller).to receive(:apply).with(action2)

      expect(logger).not_to receive(:debug)

      expect { described_class.execute(actions: actions) }.not_to raise_error
    end

    it "raises when setup of an auditor fails" do
      allow(Entitlements).to receive(:auditors).and_return([auditor1, auditor2])
      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action2).to receive(:dn).and_return("cn=action2")

      expect(auditor1).to receive(:setup).and_raise(exc)
      expect(auditor1).not_to receive(:commit)

      expect(auditor2).not_to receive(:setup)
      expect(auditor2).not_to receive(:commit)

      expect { described_class.execute(actions: actions) }.to raise_error(exc)
    end

    it "raises (but runs other auditors) when an auditor fails" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)
      allow(Entitlements).to receive(:auditors).and_return([auditor1, auditor2])

      allow(ldap_controller).to receive(:preapply)
      allow(other_controller).to receive(:preapply)

      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action1).to receive(:ou).and_return("ldap-dir")
      allow(action2).to receive(:dn).and_return("cn=action2")
      allow(action2).to receive(:ou).and_return("other-ldap-dir")
      allow(ldap_controller).to receive(:apply).with(action1)
      allow(other_controller).to receive(:apply).with(action2)

      expect(auditor1).to receive(:setup)
      expect(auditor1).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn, action2.dn]),
          provider_exception: nil
        ).and_raise(exc)
      expect(auditor1).to receive(:description).and_return("Auditor 1")

      expect(auditor2).to receive(:setup)
      expect(auditor2).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn, action2.dn]),
          provider_exception: nil
        )
      expect(auditor2).to receive(:description).and_return("Auditor 2")

      expect(logger).to receive(:debug).with("Recording data to 2 audit provider(s)")
      expect(logger).to receive(:debug).with("Audit Auditor 2 completed successfully")
      allow(logger).to receive(:error)
      expect(logger).to receive(:error).with("Audit Auditor 1 failed: RuntimeError Boom")

      expect { described_class.execute(actions: actions) }.to raise_error(exc)
    end

    it "raises when a provider fails and there are no auditors" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)
      allow(Entitlements).to receive(:auditors).and_return([])

      allow(ldap_controller).to receive(:preapply)
      allow(other_controller).to receive(:preapply)

      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action1).to receive(:ou).and_return("ldap-dir")

      allow(ldap_controller).to receive(:apply).with(action1).and_raise(exc)

      expect(action2).not_to receive(:ou_type)
      expect(other_controller).not_to receive(:apply)

      expect(logger).not_to receive(:debug)

      expect { described_class.execute(actions: actions) }.to raise_error(exc)
    end

    it "raises (but runs the auditors) when a provider fails" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)
      allow(Entitlements).to receive(:auditors).and_return([auditor1, auditor2])

      allow(ldap_controller).to receive(:preapply)
      allow(other_controller).to receive(:preapply)

      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action1).to receive(:ou).and_return("ldap-dir")
      allow(action2).to receive(:dn).and_return("cn=action2")
      allow(action2).to receive(:ou).and_return("other-ldap-dir")
      allow(ldap_controller).to receive(:apply).with(action1)
      allow(other_controller).to receive(:apply).with(action2).and_raise(exc)

      expect(auditor1).to receive(:setup)
      expect(auditor1).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn]),
          provider_exception: exc
        )
      expect(auditor1).to receive(:description).and_return("Auditor 1")

      expect(auditor2).to receive(:setup)
      expect(auditor2).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn]),
          provider_exception: exc
        )
      expect(auditor2).to receive(:description).and_return("Auditor 2")

      expect(logger).to receive(:debug).with("Recording data to 2 audit provider(s)")
      expect(logger).to receive(:debug).with("Audit Auditor 1 completed successfully")
      expect(logger).to receive(:debug).with("Audit Auditor 2 completed successfully")

      expect { described_class.execute(actions: actions) }.to raise_error(exc)
    end

    it "raises the provider's exception when a provider and auditor both fail" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)
      allow(Entitlements).to receive(:auditors).and_return([auditor1, auditor2])

      allow(ldap_controller).to receive(:preapply)
      allow(other_controller).to receive(:preapply)

      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action1).to receive(:ou).and_return("ldap-dir")
      allow(action2).to receive(:dn).and_return("cn=action2")
      allow(action2).to receive(:ou).and_return("other-ldap-dir")
      allow(ldap_controller).to receive(:apply).with(action1)
      allow(other_controller).to receive(:apply).with(action2).and_raise(exc)

      expect(auditor1).to receive(:setup)
      expect(auditor1).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn]),
          provider_exception: exc
        ).and_raise(exc2)
      expect(auditor1).to receive(:description).and_return("Auditor 1")

      expect(auditor2).to receive(:setup)
      expect(auditor2).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn]),
          provider_exception: exc
        )
      expect(auditor2).to receive(:description).and_return("Auditor 2")

      expect(logger).to receive(:debug).with("Recording data to 2 audit provider(s)")
      expect(logger).to receive(:error).with("Audit Auditor 1 failed: RuntimeError Boom Boom")
      expect(logger).to receive(:debug).with("Audit Auditor 2 completed successfully")
      allow(logger).to receive(:error) # Stack trace

      expect { described_class.execute(actions: actions) }.to raise_error(exc)
    end

    it "raises and logs a message when multiple auditors fail" do
      allow(Entitlements).to receive(:child_classes).and_return("ldap-dir" => ldap_controller, "other-ldap-dir" => other_controller)
      allow(Entitlements).to receive(:auditors).and_return([auditor1, auditor2])

      allow(ldap_controller).to receive(:preapply)
      allow(other_controller).to receive(:preapply)

      allow(action1).to receive(:dn).and_return("cn=action1")
      allow(action1).to receive(:ou).and_return("ldap-dir")
      allow(action2).to receive(:dn).and_return("cn=action2")
      allow(action2).to receive(:ou).and_return("other-ldap-dir")
      allow(ldap_controller).to receive(:apply).with(action1)
      allow(other_controller).to receive(:apply).with(action2)

      expect(auditor1).to receive(:setup)
      expect(auditor1).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn, action2.dn]),
          provider_exception: nil
        ).and_raise(exc)
      expect(auditor1).to receive(:description).and_return("Auditor 1")

      expect(auditor2).to receive(:setup)
      expect(auditor2).to receive(:commit)
        .with(
          actions: [action1, action2],
          successful_actions: Set.new([action1.dn, action2.dn]),
          provider_exception: nil
        ).and_raise(exc2)
      expect(auditor2).to receive(:description).and_return("Auditor 2")

      expect(logger).to receive(:debug).with("Recording data to 2 audit provider(s)")
      expect(logger).to receive(:warn).with("There were 2 audit exceptions. Only the first one is raised.")
      expect(logger).to receive(:error).with("Audit Auditor 1 failed: RuntimeError Boom")
      expect(logger).to receive(:error).with("Audit Auditor 2 failed: RuntimeError Boom Boom")
      allow(logger).to receive(:error) # Stack trace

      expect { described_class.execute(actions: actions) }.to raise_error(exc)
    end
  end

  describe "#validate_configuration_file!" do
    it "raises when a required attribute is missing" do
      Entitlements.config_file = fixture("config-files/required-attribute-missing.yaml")
      expect do
        described_class.validate_configuration_file!
      end.to raise_error(RuntimeError, "Entitlements configuration file is missing attribute configuration_path!")
    end

    it "raises when a required attribute has the wrong datatype" do
      Entitlements.config_file = fixture("config-files/required-attribute-wrong-datatype.yaml")
      expect do
        described_class.validate_configuration_file!
      end.to raise_error(RuntimeError, "Entitlements configuration file attribute \"configuration_path\" is supposed to be String, not Array!")
    end

    it "raises when a group has no type" do
      Entitlements.config_file = fixture("config-files/group-no-type.yaml")
      expect do
        described_class.validate_configuration_file!
      end.to raise_error(
        RuntimeError,
        "Entitlements configuration group \"foo/bar/baz\" does not properly declare a type!"
      )
    end

    it "raises when a group has an invalid type" do
      Entitlements.config_file = fixture("config-files/group-invalid-type.yaml")
      expect do
        described_class.validate_configuration_file!
      end.to raise_error(RuntimeError, "Entitlements configuration group \"foo/bar/baz\" has invalid type (\"this-is-clearly-not-valid\")")
    end

    it "returns when there are no errors" do
      Entitlements.config_file = fixture("config-files/valid.yaml")
      expect do
        described_class.validate_configuration_file!
      end.not_to raise_error
    end

    it "prefers the type defined with the OU when type and backend are defined" do
      Entitlements.config_file = fixture("config-files/backend-and-type.yaml")
      described_class.validate_configuration_file!
      group_cfg = Entitlements.config["groups"]["foo/bar/baz"]
      expect(group_cfg["type"]).to eq("ldap")
      expect(group_cfg["backend"]).to be nil
    end

    it "raises when a backend is referenced but undefined" do
      Entitlements.config_file = fixture("config-files/backend-missing.yaml")
      expect do
        described_class.validate_configuration_file!
      end.to raise_error(RuntimeError, 'Entitlements configuration group "foo/bar/baz" references non-existing backend "missing-backend"!')
    end

    it "raises when a backend does not have a type" do
      Entitlements.config_file = fixture("config-files/backend-missing-type.yaml")
      expect do
        described_class.validate_configuration_file!
      end.to raise_error(RuntimeError, 'Entitlements backend "dummy-backend" is missing a type!')
    end

    it "substitutes in values from a backend but prefers specifically configured values" do
      Entitlements.config_file = fixture("config-files/backend-valid.yaml")
      described_class.validate_configuration_file!
      group_cfg = Entitlements.config["groups"]["foo/bar/baz"]
      expect(group_cfg).to eq(
        "my-key1" => "default-value-1", "my-key2" => "specific-value-2", "type" => "dummy"
      )
    end
  end

  describe "#prefetch_people" do
    let(:ldap_obj) { instance_double(Entitlements::Data::People::LDAP) }
    let(:yaml_obj) { instance_double(Entitlements::Data::People::YAML) }

    it "raises if no people data sources are specified" do
      Entitlements.config_file = fixture("config-files/prefetch-people-invalid.yaml")
      described_class.validate_configuration_file!

      expect do
        described_class.prefetch_people
      end.to raise_error(ArgumentError, "At least one data source for people must be specified in the Entitlements configuration!")
    end

    context "when the people_data_source is not specified" do
      let(:entitlements_config_hash) do
        {
          "people" => { "yaml" => { "type" => "yaml", "config" => { "filename" => fixture("config.yaml") } } }
        }
      end

      it "raises" do
        expect do
          described_class.prefetch_people
        end.to raise_error(ArgumentError, "The Entitlements configuration must define a people_data_source!")
      end
    end

    context "when the people_data_source is invalid" do
      let(:entitlements_config_hash) do
        {
          "people" => { "yaml" => { "type" => "yaml", "config" => { "filename" => fixture("config.yaml") } } },
          "people_data_source" => "kittens"
        }

      end

      it "raises" do
        expect do
          described_class.prefetch_people
        end.to raise_error(ArgumentError, 'The people_data_source "kittens" is invalid!')
      end
    end

    context "when the people_data_source is valid" do
      let(:entitlements_config_file) { fixture("config-files/prefetch-people-valid.yaml") }

      it "constructs a hash of datasource name to object" do
        expect(Entitlements::Data::People::LDAP).to receive(:new_from_config)
          .with({
            "base"             => "ou=People,dc=kittens,dc=net",
            "ldap_binddn"      => "uid=binder,ou=People,dc=kittens,dc=net",
            "ldap_bindpw"      => "s3cr3t",
            "ldap_uri"         => "ldaps://ldap.example.net",
            "person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net"
          }).and_return(ldap_obj)
        expect(ldap_obj).to receive(:read).and_return({})

        expect(Entitlements::Data::People::YAML).to receive(:new_from_config)
          .with({
            "filename"         => "people.yaml",
            "person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net"
          }).and_return(yaml_obj)
        expect(yaml_obj).to receive(:read).and_return({})

        result = described_class.prefetch_people
        expect(result).to eq(ldap_obj)
      end
    end
  end
end
