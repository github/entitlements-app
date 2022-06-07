# frozen_string_literal: true

require_relative "../../../spec_helper"

describe Entitlements::Backend::MemberOf::Controller do
  let(:backend_config) { Entitlements.config["groups"]["memberof"] }
  let(:entitlements_config_file) { fixture("config-files/config-memberof.yaml") }
  let(:subject) { described_class.new("memberof-attr", backend_config) }
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }

  describe "#calculate" do
    let(:person) { instance_double(Entitlements::Models::Person) }
    let(:cache) { { people_obj: people_obj } }

    context "with no matching OUs" do
      let(:backend_config) { Entitlements.config["groups"]["memberof"].merge("ou" => %w[ou_three ou_four]) }

      it "raises when there are no matching groups" do
        group_notcalled = instance_double(Entitlements::Models::Group)

        group1 = instance_double(Entitlements::Models::Group)
        allow(group1).to receive(:member_strings)
          .and_return(Set.new(%w[cheetoh blackmanx RAGAMUFFIn]))

        group2 = instance_double(Entitlements::Models::Group)
        allow(group2).to receive(:member_strings)
          .and_return(Set.new(%w[blackmanx RAGAMUFFIn]))

        group3 = instance_double(Entitlements::Models::Group)
        allow(group3).to receive(:member_strings)
          .and_return(Set.new(%w[RAGAMUFFIn]))

        allow(Entitlements::Data::Groups::Calculated).to receive(:all_groups).and_return({
          "ou_one" => {
            config: {},
            groups: {
              "cn=group1,ou=MyOu,dc=kittens,dc=net" => group_notcalled,
              "cn=group2,ou=MyOu,dc=kittens,dc=net" => group_notcalled,
              "cn=group3,ou=MyOu,dc=kittens,dc=net" => group_notcalled,
              "cn=group4,ou=MyOu,dc=kittens,dc=net" => group_notcalled
            }
          },
          "ou_two" => {
            config: { "memberof_attribute" => "chickenEntitlements" },
            groups: {
              "cn=group1,ou=MyOu,dc=kittens,dc=net" => group1,
              "cn=group2,ou=MyOu,dc=kittens,dc=net" => group2,
              "cn=group3,ou=MyOu,dc=kittens,dc=net" => group3
            }
          }
        })

        expect { subject.calculate }.to raise_error("memberOf emulator found no OUs matching: ou_three, ou_four")
      end
    end

    it "produces the expected set of actions" do
      expect(logger).to receive(:debug).with("Calculating memberOf attributes for configured groups")
      expect(logger).to receive(:debug).with(%r{Loading people from ".+/unit/fixtures/people.yaml"})

      group_notcalled = instance_double(Entitlements::Models::Group)

      group1 = instance_double(Entitlements::Models::Group)
      allow(group1).to receive(:member_strings)
        .and_return(Set.new(%w[cheetoh blackmanx RAGAMUFFIn]))

      group2 = instance_double(Entitlements::Models::Group)
      allow(group2).to receive(:member_strings)
        .and_return(Set.new(%w[blackmanx RAGAMUFFIn]))

      group3 = instance_double(Entitlements::Models::Group)
      allow(group3).to receive(:member_strings)
        .and_return(Set.new(%w[RAGAMUFFIn]))

      allow(Entitlements::Data::Groups::Calculated).to receive(:all_groups).and_return({
        "ou_one" => {
          config: {},
          groups: {
            "cn=group1,ou=MyOu,dc=kittens,dc=net" => group_notcalled,
            "cn=group2,ou=MyOu,dc=kittens,dc=net" => group_notcalled,
            "cn=group3,ou=MyOu,dc=kittens,dc=net" => group_notcalled,
            "cn=group4,ou=MyOu,dc=kittens,dc=net" => group_notcalled
          }
        },
        "ou_two" => {
          config: { "memberof_attribute" => "chickenEntitlements" },
          groups: {
            "cn=group1,ou=MyOu,dc=kittens,dc=net" => group1,
            "cn=group2,ou=MyOu,dc=kittens,dc=net" => group2,
            "cn=group3,ou=MyOu,dc=kittens,dc=net" => group3
          }
        }
      })

      # Hack some groups into some people.
      people_obj.read("blackmanx").instance_variable_set("@original_attributes",
        { "chickenEntitlements" => Set.new(%w[group1 group3 group4].map { |g| "cn=#{g},ou=MyOu,dc=kittens,dc=net" }) }
      )
      people_obj.read("russianblue").instance_variable_set("@original_attributes",
        { "chickenEntitlements" => Set.new(%w[group1 group3 group4].map { |g| "cn=#{g},ou=MyOu,dc=kittens,dc=net" }) }
      )
      people_obj.read("RAGAMUFFIn").instance_variable_set("@original_attributes",
        { "chickenEntitlements" => Set.new(%w[group1 group2 group4].map { |g| "cn=#{g},ou=MyOu,dc=kittens,dc=net" }) }
      )
      people_obj.read("cheetoh").instance_variable_set("@original_attributes",
        { "chickenEntitlements" => Set.new(%w[group1].map { |g| "cn=#{g},ou=MyOu,dc=kittens,dc=net" }) }
      )

      expect(subject).to receive(:print_differences).with(people_obj.read["RAGAMUFFIn"])
      expect(subject).to receive(:print_differences).with(people_obj.read["blackmanx"])
      expect(subject).to receive(:print_differences).with(people_obj.read["russianblue"])
      expect(subject).not_to receive(:print_differences).with(people_obj.read["cheetoh"])

      subject.calculate
      expect(subject.actions).to be_a_kind_of(Array)
      expect(subject.actions.size).to eq(3)

      change1 = subject.actions.find { |action| action.dn == "RAGAMUFFIn" }
      expect(change1.updated["chickenEntitlements"]).to eq(%w[group1 group2 group3].map { |g| "cn=#{g},ou=MyOu,dc=kittens,dc=net" })

      change2 = subject.actions.find { |action| action.dn == "blackmanx" }
      expect(change2.updated["chickenEntitlements"]).to eq(%w[group1 group2].map { |g| "cn=#{g},ou=MyOu,dc=kittens,dc=net" })

      change3 = subject.actions.find { |action| action.dn == "russianblue" }
      expect(change3.updated["chickenEntitlements"]).to eq([])
    end
  end

  describe "#print_differences" do
    let(:person) { instance_double(Entitlements::Models::Person) }

    it "returns if there were no changes in the person" do
      allow(person).to receive(:attribute_changes).and_return({})
      expect(logger).not_to receive(:info)
      expect(subject.print_differences(person)).to be nil
    end

    it "prints log messages for the expected cases" do
      allow(person).to receive(:attribute_changes).and_return(
        "addedStringAttr"    => "Added kittens",
        "deletedStringAttr"  => nil,
        "modifiedStringAttr" => "Modified kittens",
        "addedArrayAttr"     => %w[buzz fizz],
        "deletedArrayAttr"   => nil,
        "modifiedArrayAttr"  => %w[blah blarg],
        "edgeCaseOne"        => "My String Here",
        "edgeCaseTwo"        => %w[ArrayItem2]
      )
      allow(person).to receive(:original).with("addedArrayAttr").and_return(nil)
      allow(person).to receive(:original).with("deletedArrayAttr").and_return(%w[foo bar baz])
      allow(person).to receive(:original).with("modifiedArrayAttr").and_return(%w[blah biff])
      allow(person).to receive(:original).with("addedStringAttr").and_return(nil)
      allow(person).to receive(:original).with("deletedStringAttr").and_return("Former kittens")
      allow(person).to receive(:original).with("modifiedStringAttr").and_return("Original kittens")
      allow(person).to receive(:original).with("edgeCaseOne").and_return(%w[Original ArrayItem])
      allow(person).to receive(:original).with("edgeCaseTwo").and_return("Original edge case")

      allow(person).to receive(:uid).and_return("bob")

      expect(logger).to receive(:info).with("Person bob attribute changes:")
      expect(logger).to receive(:info).with(". ADD attribute addedArrayAttr:")
      expect(logger).to receive(:info).with(".   + buzz")
      expect(logger).to receive(:info).with(".   + fizz")
      expect(logger).to receive(:info).with(". REMOVE attribute deletedArrayAttr: 3 entries")
      expect(logger).to receive(:info).with(". MODIFY attribute modifiedArrayAttr:")
      expect(logger).to receive(:info).with(".  - \"biff\"")
      expect(logger).to receive(:info).with(".  + \"blarg\"")
      expect(logger).to receive(:info).with(". MODIFY attribute edgeCaseOne:")
      expect(logger).to receive(:info).with(".  - (Array)")
      expect(logger).to receive(:info).with(".  + \"My String Here\"")
      expect(logger).to receive(:info).with(". MODIFY attribute edgeCaseTwo:")
      expect(logger).to receive(:info).with(".  - (String)")
      expect(logger).to receive(:info).with(".  + [\"ArrayItem2\"]")
      expect(logger).to receive(:info).with(". ADD attribute addedStringAttr: \"Added kittens\"")
      expect(logger).to receive(:info).with(". REMOVE attribute deletedStringAttr: \"Former kittens\"")
      expect(logger).to receive(:info).with(". MODIFY attribute modifiedStringAttr:")
      expect(logger).to receive(:info).with(".  - \"Original kittens\"")
      expect(logger).to receive(:info).with(".  + \"Modified kittens\"")

      expect(subject.print_differences(person)).to be nil
    end
  end

  describe "#apply" do
    let(:action) { instance_double(Entitlements::Models::Action) }
    let(:ldap) { instance_double(Entitlements::Service::LDAP) }

    it "calls ldap modify with the changes" do
      allow(subject).to receive(:ldap).and_return(ldap)
      allow(ldap).to receive(:person_dn_format).and_return("uid=%KEY%,ou=People,dc=kittens,dc=net")

      person = people_obj.read["blackmanx"]
      attrib = { "shellentitlements" => Set.new(["cn=foo,ou=bar,dc=kittens,dc=net"]) }
      person.instance_variable_set("@original_attributes", attrib)
      person["shellentitlements"] = ["cn=bar,ou=bar,dc=kittens,dc=net"]
      allow(action).to receive(:updated).and_return(person)

      expect(logger).to receive(:debug).with("APPLY: Upsert shellentitlements to blackmanx")
      expect(ldap).to receive(:modify).with(
        "uid=blackmanx,ou=People,dc=kittens,dc=net",
        {"shellentitlements"=>["cn=bar,ou=bar,dc=kittens,dc=net"]}
      ).and_return(true)

      expect { subject.apply(action) }.not_to raise_error
    end

    it "calls ldap modify with the addition" do
      allow(subject).to receive(:ldap).and_return(ldap)
      allow(ldap).to receive(:person_dn_format).and_return("uid=%KEY%,ou=People,dc=kittens,dc=net")

      person = people_obj.read["blackmanx"]
      attrib = { "shellentitlements" => Set.new(["cn=foo,ou=bar,dc=kittens,dc=net"]) }
      person.instance_variable_set("@original_attributes", attrib)
      person["shellentitlements"] = nil
      allow(action).to receive(:updated).and_return(person)

      expect(logger).to receive(:debug).with("APPLY: Delete shellentitlements from blackmanx")
      expect(ldap).to receive(:modify).with(
        "uid=blackmanx,ou=People,dc=kittens,dc=net",
        {"shellentitlements"=>nil}
      ).and_return(true)

      expect { subject.apply(action) }.not_to raise_error
    end

    it "raises if ldap modify operation fails" do
      allow(subject).to receive(:ldap).and_return(ldap)
      allow(ldap).to receive(:person_dn_format).and_return("uid=%KEY%,ou=People,dc=kittens,dc=net")

      person = people_obj.read["blackmanx"]
      attrib = { "shellentitlements" => Set.new(["cn=foo,ou=bar,dc=kittens,dc=net"]) }
      person.instance_variable_set("@original_attributes", attrib)
      person["shellentitlements"] = ["cn=bar,ou=bar,dc=kittens,dc=net"]
      allow(action).to receive(:updated).and_return(person)

      expect(logger).to receive(:debug).with("APPLY: Upsert shellentitlements to blackmanx")
      expect(logger).to receive(:warn).with("DID NOT APPLY: Changes to blackmanx failed!")
      expect(ldap).to receive(:modify).with(
        "uid=blackmanx,ou=People,dc=kittens,dc=net",
        {"shellentitlements"=>["cn=bar,ou=bar,dc=kittens,dc=net"]}
      ).and_return(false)

      expect do
        subject.apply(action)
      end.to raise_error(RuntimeError, "LDAP modify error on uid=blackmanx,ou=People,dc=kittens,dc=net!")
    end
  end
end
