# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::Backend::BaseController do
  let(:group_name) { "foo-ldap" }
  let(:backend_config) { {} }
  let(:subject) { described_class.new(group_name, backend_config) }

  describe "#print_differences" do
    let(:key) { "sample_ou" }
    let(:dn1) { "uid=one,ou=People,dc=kittens,dc=net" }
    let(:dn2) { "uid=two,ou=People,dc=kittens,dc=net" }
    let(:dn3) { "uid=three,ou=People,dc=kittens,dc=net" }
    let(:dn4) { "uid=four,ou=People,dc=kittens,dc=net" }

    context "with adds, removes, and changes" do
      it "displays the info" do
        added_dn = "cn=added,ou=Sample,dc=kittens,dc=net"
        added_group = instance_double(Entitlements::Models::Group)
        allow(added_group).to receive(:member_strings).and_return([dn1, dn2])
        added_action = Entitlements::Models::Action.new(added_dn, nil, added_group, key)

        removed_dn = "cn=removed,ou=Sample,dc=kittens,dc=net"
        removed_group = instance_double(Entitlements::Models::Group)
        removed_action = Entitlements::Models::Action.new(removed_dn, removed_group, nil, key)

        changed_dn = "cn=changed,ou=Sample,dc=kittens,dc=net"
        changed_group_before = instance_double(Entitlements::Models::Group)
        allow(changed_group_before).to receive(:member_strings).and_return([dn1, dn2])
        allow(changed_group_before).to receive(:description).and_return("My awesome group")
        changed_group_after = instance_double(Entitlements::Models::Group)
        allow(changed_group_after).to receive(:member_strings).and_return([dn1, dn3])
        allow(changed_group_after).to receive(:description).and_return("My awesome group")
        changed_action = Entitlements::Models::Action.new(changed_dn, changed_group_before, changed_group_after, key)

        expect(logger).to receive(:info).with("ADD #{added_dn} to sample_ou (Members: one,two)")
        expect(logger).to receive(:info).with("DELETE #{removed_dn} from sample_ou")
        expect(logger).to receive(:info).with("CHANGE #{changed_dn} in sample_ou")
        expect(logger).to receive(:info).with(".  + uid=three,ou=People,dc=kittens,dc=net")
        expect(logger).to receive(:info).with(".  - uid=two,ou=People,dc=kittens,dc=net")

        subject.print_differences(key: key, added: [added_action], removed: [removed_action], changed: [changed_action])
      end
    end

    context "with only changes" do
      it "displays the info" do
        allow(Entitlements).to receive(:config).and_return({ "groups" => { key => { "type" => "ldap" } } })

        changed_dn = "cn=changed,ou=Sample,dc=kittens,dc=net"
        changed_group_before = instance_double(Entitlements::Models::Group)
        allow(changed_group_before).to receive(:member_strings).and_return([dn1, dn2])
        allow(changed_group_before).to receive(:description).and_return("My awesome group")
        changed_group_after = instance_double(Entitlements::Models::Group)
        allow(changed_group_after).to receive(:member_strings).and_return([dn1, dn3])
        allow(changed_group_after).to receive(:description).and_return("My updated group")
        changed_action = Entitlements::Models::Action.new(changed_dn, changed_group_before, changed_group_after, key)

        expect(logger).to receive(:info).with("CHANGE #{changed_dn} in sample_ou")
        expect(logger).to receive(:info).with(".  + uid=three,ou=People,dc=kittens,dc=net")
        expect(logger).to receive(:info).with(".  - uid=two,ou=People,dc=kittens,dc=net")
        expect(logger).to receive(:info).with("METADATA CHANGE #{changed_dn} in sample_ou")
        expect(logger).to receive(:info).with("- Old description: \"My awesome group\"")
        expect(logger).to receive(:info).with("+ New description: \"My updated group\"")

        subject.print_differences(key: key, added: [], removed: [], changed: [changed_action])
      end
    end

    context "with only a description change" do
      it "displays the info" do
        allow(Entitlements).to receive(:config).and_return({ "groups" => { key => { "type" => "ldap" } } })

        changed_dn = "cn=changed,ou=Sample,dc=kittens,dc=net"
        changed_group_before = instance_double(Entitlements::Models::Group)
        allow(changed_group_before).to receive(:member_strings).and_return([dn1, dn2])
        allow(changed_group_before).to receive(:description).and_return("My awesome group")
        changed_group_after = instance_double(Entitlements::Models::Group)
        allow(changed_group_after).to receive(:member_strings).and_return([dn1, dn2])
        allow(changed_group_after).to receive(:description).and_return("My updated group")
        changed_action = Entitlements::Models::Action.new(changed_dn, changed_group_before, changed_group_after, key)

        expect(logger).to receive(:info).with("METADATA CHANGE #{changed_dn} in sample_ou")
        expect(logger).to receive(:info).with("- Old description: \"My awesome group\"")
        expect(logger).to receive(:info).with("+ New description: \"My updated group\"")

        subject.print_differences(key: key, added: [], removed: [], changed: [changed_action])
      end
    end

    context "with a change due only to case differences" do
      it "filters case-only differences and displays remainder" do
        allow(Entitlements).to receive(:config).and_return({ "groups" => { key => { "type" => "ldap" } } })

        dn4a = "uid=FOUR,ou=People,dc=kittens,dc=net"
        dn4b = "uid=four,ou=People,dc=kittens,dc=net"

        changed_dn = "cn=changed,ou=Sample,dc=kittens,dc=net"
        changed_group_before = instance_double(Entitlements::Models::Group)
        allow(changed_group_before).to receive(:member_strings).and_return([dn1, dn2, dn4a])
        allow(changed_group_before).to receive(:description).and_return("My awesome group")
        changed_group_after = instance_double(Entitlements::Models::Group)
        allow(changed_group_after).to receive(:member_strings).and_return([dn1, dn3, dn4b])
        allow(changed_group_after).to receive(:description).and_return("My updated group")
        changed_action = Entitlements::Models::Action.new(changed_dn, changed_group_before, changed_group_after, key)

        expect(logger).to receive(:info).with("CHANGE #{changed_dn} in sample_ou")
        expect(logger).to receive(:info).with(".  + uid=three,ou=People,dc=kittens,dc=net")
        expect(logger).to receive(:info).with(".  - uid=two,ou=People,dc=kittens,dc=net")
        expect(logger).to receive(:info).with("METADATA CHANGE #{changed_dn} in sample_ou")
        expect(logger).to receive(:info).with("- Old description: \"My awesome group\"")
        expect(logger).to receive(:info).with("+ New description: \"My updated group\"")

        subject.print_differences(key: key, added: [], removed: [], changed: [changed_action])
      end
    end
  end

  describe "#change_count" do
    it "returns the count of the 'actions'" do
      action1 = instance_double(Entitlements::Models::Action)
      action2 = instance_double(Entitlements::Models::Action)
      allow(subject).to receive(:actions).and_return([action1, action2])
      expect(subject.change_count).to eq(2)
    end
  end
end
