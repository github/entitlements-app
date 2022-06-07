# frozen_string_literal: true
require_relative "../../../spec_helper"

describe Entitlements::Backend::LDAP::Controller do
  let(:backend_config) { base_backend_config }
  let(:base_backend_config) do
    {
      "base"              => "ou=foo,dc=example,dc=net",
      "create_if_missing" => true,
      "ldap_binddn"       => "uid=binder,ou=People,dc=example,dc=net",
      "ldap_bindpw"       => "s3cr3t",
      "ldap_uri"          => "ldaps://ldap.example.net",
      "person_dn_format"  => "uid=%KEY%,ou=People,dc=example,dc=net"
    }
  end
  let(:group_name) { "foo-ldap" }
  let(:provider) { instance_double(Entitlements::Backend::LDAP::Provider) }
  let(:ldap) { instance_double(Entitlements::Service::LDAP) }
  let(:subject) { described_class.new(group_name, backend_config) }

  describe "#prefetch" do
    it "reads full membership of the OU" do
      expect(logger).to receive(:debug)
        .with("Pre-fetching group membership in foo-ldap (ou=foo,dc=example,dc=net) from LDAP")
      expect(subject).to receive(:provider).and_return(provider)
      expect(provider).to receive(:read_all).with("ou=foo,dc=example,dc=net")
      subject.prefetch
    end
  end

  describe "#validate" do
    context "when the object is a mirror OU" do
      let(:backend_config) { base_backend_config.merge("mirror" => "fizz/buzz") }

      it "calls the validate mirror" do
        expect(Entitlements::Util::Mirror).to receive(:validate_mirror!).with(group_name)
        subject.validate
      end
    end

    context "when the object is not a mirror OU" do
      it "does not all the validate mirror" do
        expect(Entitlements::Util::Mirror).not_to receive(:validate_mirror!)
        subject.validate
      end
    end
  end

  describe "#change_count" do
    context "when the OU needs to be added" do
      it "displays the action count, plus one" do
        allow(subject).to receive(:ou_needs_to_be_created?).and_return(true)
        allow(subject).to receive(:actions).and_return([:a, :b, :c])
        expect(subject.change_count).to eq(4)
      end
    end

    context "when the OU does not need to be added" do
      it "displays the action count" do
        allow(subject).to receive(:ou_needs_to_be_created?).and_return(false)
        allow(subject).to receive(:actions).and_return([:a, :b, :c])
        expect(subject.change_count).to eq(3)
      end
    end
  end

  describe "#calculate" do
    it "calculates, displays differences, and populates actions" do
      allow(subject).to receive(:ou_needs_to_be_created?).and_return(true)
      allow(subject).to receive(:provider).and_return(provider)
      allow(subject).to receive(:ldap).and_return(ldap)

      existing = Set.new(%w[
        cn=group-to-delete,ou=foo,dc=example,dc=net
        cn=group-unchanged,ou=foo,dc=example,dc=net
        cn=group-updated,ou=foo,dc=example,dc=net
      ])
      expect(provider).to receive(:read_all).with("ou=foo,dc=example,dc=net").and_return(existing)

      proposed = Set.new(%w[
        cn=group-to-add,ou=foo,dc=example,dc=net
        cn=group-unchanged,ou=foo,dc=example,dc=net
        cn=group-updated,ou=foo,dc=example,dc=net
      ])
      expect(Entitlements::Data::Groups::Calculated).to receive(:read_all)
        .with(group_name, base_backend_config).and_return(proposed)

      group_to_add = instance_double(Entitlements::Models::Group)
      allow(Entitlements::Data::Groups::Calculated).to receive(:read)
        .with("cn=group-to-add,ou=foo,dc=example,dc=net").and_return(group_to_add)

      group_to_delete = instance_double(Entitlements::Models::Group)
      allow(provider).to receive(:read)
        .with("cn=group-to-delete,ou=foo,dc=example,dc=net").and_return(group_to_delete)

      group_to_update_1 = instance_double(Entitlements::Models::Group)
      allow(Entitlements::Data::Groups::Calculated).to receive(:read)
        .with("cn=group-updated,ou=foo,dc=example,dc=net").and_return(group_to_update_1)

      group_to_update_2 = instance_double(Entitlements::Models::Group)
      allow(provider).to receive(:read)
        .with("cn=group-updated,ou=foo,dc=example,dc=net").and_return(group_to_update_2)

      allow(group_to_update_1).to receive(:equals?).with(group_to_update_2).and_return(false)
      allow(group_to_update_2).to receive(:equals?).with(group_to_update_1).and_return(false)

      group_unchanged = instance_double(Entitlements::Models::Group)
      allow(Entitlements::Data::Groups::Calculated).to receive(:read)
        .with("cn=group-unchanged,ou=foo,dc=example,dc=net").and_return(group_unchanged)
      allow(provider).to receive(:read)
        .with("cn=group-unchanged,ou=foo,dc=example,dc=net").and_return(group_unchanged)

      allow(group_unchanged).to receive(:equals?).with(group_unchanged).and_return(true)

      expect(subject).to receive(:print_differences)

      subject.calculate

      actions = subject.send(:actions)
      expect(actions).to be_a_kind_of(Array)
      expect(actions.size).to eq(3)
      expect(actions[0].dn).to eq("cn=group-to-add,ou=foo,dc=example,dc=net")
      expect(actions[0].existing).to eq(nil)
      expect(actions[0].updated).to eq(group_to_add)
      expect(actions[1].dn).to eq("cn=group-to-delete,ou=foo,dc=example,dc=net")
      expect(actions[1].existing).to eq(group_to_delete)
      expect(actions[1].updated).to eq(nil)
      expect(actions[2].dn).to eq("cn=group-updated,ou=foo,dc=example,dc=net")
      expect(actions[2].existing).to eq(group_to_update_2)
      expect(actions[2].updated).to eq(group_to_update_1)
    end
  end

  describe "#preapply" do
    context "when create_if_missing is false" do
      let(:backend_config) { base_backend_config.merge("create_if_missing" => false) }

      it "does nothing" do
        expect { subject.preapply }.not_to raise_error
      end
    end

    context "when the OU needs to be added" do
      it "logs messages and upserts OU" do
        allow(subject).to receive(:ldap).and_return(ldap)
        expect(ldap).to receive(:exists?).with("ou=foo,dc=example,dc=net").and_return(false)
        expect(ldap).to receive(:upsert).with(
          attributes: { "objectClass" => "organizationalUnit" },
          dn: "ou=foo,dc=example,dc=net"
        ).and_return(true)
        expect(logger).to receive(:debug).with("OU create_if_missing: ou=foo,dc=example,dc=net needs to be created")
        expect(logger).to receive(:debug).with("APPLY: Creating ou=foo,dc=example,dc=net")

        expect { subject.preapply }.not_to raise_error
      end

      it "warns if it cannot upsert the OU" do
        allow(subject).to receive(:ldap).and_return(ldap)
        expect(ldap).to receive(:exists?).with("ou=foo,dc=example,dc=net").and_return(false)
        expect(ldap).to receive(:upsert).with(
          attributes: { "objectClass" => "organizationalUnit" },
          dn: "ou=foo,dc=example,dc=net"
        ).and_return(false)
        expect(logger).to receive(:debug).with("OU create_if_missing: ou=foo,dc=example,dc=net needs to be created")
        expect(logger).to receive(:warn).with("DID NOT APPLY: Changes not needed to ou=foo,dc=example,dc=net")

        expect { subject.preapply }.not_to raise_error
      end
    end

    context "when the OU does not need to be added" do
      it "logs messages but does not upsert OU" do
        allow(subject).to receive(:ldap).and_return(ldap)
        expect(ldap).to receive(:exists?).with("ou=foo,dc=example,dc=net").and_return(true)
        expect(ldap).not_to receive(:upsert)
        expect(logger).to receive(:debug).with("OU create_if_missing: ou=foo,dc=example,dc=net already exists")

        expect { subject.preapply }.not_to raise_error
      end
    end
  end

  describe "#apply" do
    let(:dn) { "cn=foo,ou=foo,dc=example,dc=net" }
    let(:ou) { "foo-ou" }
    let(:existing) { instance_double(Entitlements::Models::Group) }
    let(:updated) { instance_double(Entitlements::Models::Group) }
    let(:action) { Entitlements::Models::Action.new(dn, existing, updated, ou) }
    let(:entitlements_config_hash) { { "groups" => { "foo-ou" => {} } } }

    context "when deleting an entry" do
      let(:updated) { nil }

      it "deletes an entry" do
        allow(subject).to receive(:ldap).and_return(ldap)
        expect(ldap).to receive(:delete).with("cn=foo,ou=foo,dc=example,dc=net")
        expect(logger).to receive(:debug).with("APPLY: Deleting cn=foo,ou=foo,dc=example,dc=net")

        subject.apply(action)
      end
    end

    context "when adding an entry" do
      let(:existing) { nil }

      it "upserts an entry" do
        allow(subject).to receive(:provider).and_return(provider)

        expect(provider).to receive(:upsert).with(updated, {}).and_return(true)
        expect(logger).to receive(:debug).with("APPLY: Upserting cn=foo,ou=foo,dc=example,dc=net")

        subject.apply(action)
      end
    end

    context "when updating an entry" do
      it "warns when an upsert fails" do
        allow(subject).to receive(:provider).and_return(provider)

        expect(provider).to receive(:upsert).with(updated, {}).and_return(false)
        expect(logger).to receive(:warn).with("DID NOT APPLY: Changes not needed to cn=foo,ou=foo,dc=example,dc=net")
        expect(logger).to receive(:debug).with(/^Old:/)
        expect(logger).to receive(:debug).with(/^New:/)

        subject.apply(action)
      end
    end
  end
end
