# frozen_string_literal: true
require_relative "../../spec_helper"
require "ostruct"

describe Entitlements::Service::LDAP do
  let(:person_dn_format) { "uid=%KEY%,ou=People,dc=kittens,dc=net" }

  let(:subject) do
    described_class.new(
      addr: "ldaps://ldap.example.net:636",
      binddn: "uid=some-user,ou=system-accounts,dc=example,dc=net",
      bindpw: "passw0rd",
      person_dn_format: person_dn_format
    )
  end

  let(:logger) { Entitlements.dummy_logger }

  let(:entry1) { instance_double(Net::LDAP::Entry) }
  let(:dn1) { "uid=evilmanx,ou=People,dc=kittens,dc=net" }

  let(:entry2) { instance_double(Net::LDAP::Entry) }
  let(:dn2) { "uid=evilragamuffin,ou=People,dc=kittens,dc=net" }

  let(:ldap) { instance_double(Net::LDAP) }

  describe "#new_with_cache" do
    let(:obj1) { instance_double(described_class) }
    let(:obj1b) { instance_double(described_class) }
    let(:obj2) { instance_double(described_class) }

    it "returns the expected objects" do
      allow(described_class).to receive(:new)
        .with(addr: "a1", binddn: "dn1", bindpw: "pw1", ca_file: nil, disable_ssl_verification: false, person_dn_format: person_dn_format).and_return(obj1)
      allow(described_class).to receive(:new)
        .with(addr: "a1", binddn: "dn1", bindpw: "pw1", ca_file: nil, disable_ssl_verification: true, person_dn_format: person_dn_format).and_return(obj1b)
      allow(described_class).to receive(:new)
        .with(addr: "a2", binddn: "dn2", bindpw: "pw2", ca_file: nil, disable_ssl_verification: false, person_dn_format: person_dn_format).and_return(obj2)

      expect(described_class.new_with_cache(addr: "a1", binddn: "dn1", bindpw: "pw1", person_dn_format: person_dn_format)).to eq(obj1)
      expect(described_class.new_with_cache(addr: "a1", binddn: "dn1", bindpw: "pw1", person_dn_format: person_dn_format)).to eq(obj1)
      expect(described_class.new_with_cache(addr: "a1", binddn: "dn1", bindpw: "pw1", disable_ssl_verification: true, person_dn_format: person_dn_format)).to eq(obj1b)
      expect(described_class.new_with_cache(addr: "a1", binddn: "dn1", bindpw: "pw1", disable_ssl_verification: true, person_dn_format: person_dn_format)).to eq(obj1b)
      expect(described_class.new_with_cache(addr: "a2", binddn: "dn2", bindpw: "pw2", person_dn_format: person_dn_format)).to eq(obj2)
      expect(described_class.new_with_cache(addr: "a2", binddn: "dn2", bindpw: "pw2", person_dn_format: person_dn_format)).to eq(obj2)
    end
  end

  describe "#ldap" do
    context "without ldap SSL" do
      let(:subject) do
        described_class.new(
          addr: "ldap://ldap.example.net",
          binddn: "uid=some-user,ou=system-accounts,dc=example,dc=net",
          bindpw: "passw0rd",
          person_dn_format: person_dn_format
        )
      end

      it "constructs the object with encryption disabled" do
        obj = instance_double(Net::LDAP)
        expect(Net::LDAP)
          .to receive(:new)
          .with(
            host: "ldap.example.net",
            port: 389,
            encryption: { method: nil },
            auth: {
              method: :simple,
              username: "uid=some-user,ou=system-accounts,dc=example,dc=net",
              password: "passw0rd"
            }
          ).and_return(obj)
        expect(obj).to receive(:bind)
        expect(obj).to receive(:get_operation_result).and_return(OpenStruct.new(code: 0))

        expect(logger).to receive(:debug).with("Creating connection to ldap.example.net port 389")
        expect(logger).to receive(:debug).with('Binding with user "uid=some-user,ou=system-accounts,dc=example,dc=net" with simple password authentication')
        expect(logger).to receive(:debug).with("Successfully authenticated to ldap.example.net port 389")

        expect(subject.send(:ldap)).to eq(obj)
      end
    end

    context "happy path" do
      it "binds, logs, and returns the object" do
        obj = instance_double(Net::LDAP)
        expect(Net::LDAP)
          .to receive(:new)
          .with(
            host: "ldap.example.net",
            port: 636,
            encryption: {
              method: :simple_tls,
              tls_options: { verify_mode: 1 }
            },
            auth: {
              method: :simple,
              username: "uid=some-user,ou=system-accounts,dc=example,dc=net",
              password: "passw0rd"
            }
          ).and_return(obj)
        expect(obj).to receive(:bind)
        expect(obj).to receive(:get_operation_result).and_return(OpenStruct.new(code: 0))

        expect(logger).to receive(:debug).with("Creating connection to ldap.example.net port 636")
        expect(logger).to receive(:debug).with('Binding with user "uid=some-user,ou=system-accounts,dc=example,dc=net" with simple password authentication')
        expect(logger).to receive(:debug).with("Successfully authenticated to ldap.example.net port 636")

        expect(subject.send(:ldap)).to eq(obj)
      end
    end

    context "failure path" do
      it "logs and raises an exception" do
        obj = instance_double(Net::LDAP)
        expect(Net::LDAP).to receive(:new).and_return(obj)
        expect(obj).to receive(:bind)
        expect(obj).to receive(:get_operation_result).and_return(OpenStruct.new(code: 1, message: "Kitten cuteness override"))

        expect(logger).to receive(:debug).with("Creating connection to ldap.example.net port 636")
        expect(logger).to receive(:debug).with('Binding with user "uid=some-user,ou=system-accounts,dc=example,dc=net" with simple password authentication')
        expect(logger).to receive(:fatal).with("Kitten cuteness override")

        expect { subject.send(:ldap) }.to raise_error(Entitlements::Service::LDAP::ConnectionError)
      end
    end

    context "with a CA specified" do
      let(:subject) do
        described_class.new(
          addr: "ldaps://ldap.example.net:636",
          binddn: "uid=some-user,ou=system-accounts,dc=example,dc=net",
          bindpw: "passw0rd",
          ca_file: "/etc/ssl/my-awesome-ca.crt",
          person_dn_format: person_dn_format
        )
      end

      it "binds, logs, and returns the object" do
        obj = instance_double(Net::LDAP)
        expect(Net::LDAP)
          .to receive(:new)
          .with(
            host: "ldap.example.net",
            port: 636,
            encryption: {
              method: :simple_tls,
              tls_options: { ca_file: "/etc/ssl/my-awesome-ca.crt", verify_mode: 1 }
            },
            auth: {
              method: :simple,
              username: "uid=some-user,ou=system-accounts,dc=example,dc=net",
              password: "passw0rd"
            }
          ).and_return(obj)
        expect(obj).to receive(:bind)
        expect(obj).to receive(:get_operation_result).and_return(OpenStruct.new(code: 0))

        expect(logger).to receive(:debug).with("Creating connection to ldap.example.net port 636")
        expect(logger).to receive(:debug).with('Binding with user "uid=some-user,ou=system-accounts,dc=example,dc=net" with simple password authentication')
        expect(logger).to receive(:debug).with("Successfully authenticated to ldap.example.net port 636")

        expect(subject.send(:ldap)).to eq(obj)
      end
    end
  end

  describe "#search" do
    it "raises a duplicate entry error if the same index key is reassigned" do
      filter = Net::LDAP::Filter.eq("manager", "uid=evilbacon,ou=People,dc=example,dc=net")
      expect(subject).to receive(:ldap).and_return(ldap)
      allow(ldap).to receive(:search)
        .with(
          base: "ou=People,dc=example,dc=net",
          filter: filter,
          attributes: %w[githubdotcomid kittens manager],
          scope: Net::LDAP::SearchScope_WholeSubtree,
          return_result: false
        ).and_yield(entry1).and_yield(entry2)
      allow(entry1).to receive(:dn).and_return(dn1)
      allow(entry2).to receive(:dn).and_return(dn2)
      allow(entry1).to receive(:[]).with("kittens").and_return("awesome")
      allow(entry2).to receive(:[]).with("kittens").and_return("awesome")

      expect do
        subject.search(
          base: "ou=People,dc=example,dc=net",
          filter: filter,
          attrs: %w[GithubDotComID kittens manager],
          index: "kittens"
        )
      end.to raise_error(
        Entitlements::Service::LDAP::DuplicateEntryError,
        'uid=evilragamuffin,ou=People,dc=kittens,dc=net and uid=evilmanx,ou=People,dc=kittens,dc=net have the same value of kittens = "awesome"'
      )
    end

    it "raises an entry error if the indexed field does not exist in the entry" do
      filter = Net::LDAP::Filter.eq("kittens", "awesome")
      expect(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:search)
        .with(
          base: "ou=People,dc=example,dc=net",
          filter: filter,
          attributes: %w[githubdotcomid manager],
          scope: Net::LDAP::SearchScope_WholeSubtree,
          return_result: false
        ).and_yield(entry1).and_yield(entry2)
      allow(entry1).to receive(:[]).with("kittens").and_return(nil)
      allow(entry1).to receive(:dn).and_return(dn1)
      allow(entry2).to receive(:[]).with("kittens").and_return(nil)
      allow(entry2).to receive(:dn).and_return(dn2)

      expect do
        subject.search(
          base: "ou=People,dc=example,dc=net",
          filter: filter,
          attrs: %w[GithubDotComID manager],
          index: "kittens"
        )
      end.to raise_error(
        Entitlements::Service::LDAP::EntryError,
        'uid=evilmanx,ou=People,dc=kittens,dc=net has no value for "kittens"'
      )
    end

    it "returns the result as a Net::LDAP::Entry object searching for a DN" do
      expect(subject).to receive(:ldap).and_return(ldap)
      expect(logger).to receive(:debug).with(/LDAP Search: filter=nil base="cn=bar,ou=foo,dc=example,dc=net"/)
      expect(logger).to receive(:debug).with(/Completed search: 2 result\(s\)/)
      expect(ldap).to receive(:search).with(
        base: "cn=bar,ou=foo,dc=example,dc=net",
        filter: nil,
        attributes: %w[githubdotcomid manager],
        scope: Net::LDAP::SearchScope_BaseObject,
        return_result: false
      ).and_yield(entry1).and_yield(entry2)
      allow(entry1).to receive(:dn).and_return(dn1)
      allow(entry2).to receive(:dn).and_return(dn2)

      result = subject.search(
        base: "cn=bar,ou=foo,dc=example,dc=net",
        attrs: %w[GithubDotComID manager],
        index: :dn,
        scope: Net::LDAP::SearchScope_BaseObject
      )
      expect(result).to eq(dn1 => entry1, dn2 => entry2)
    end

    it "returns the result as a Net::LDAP::Entry object searching for a field" do
      filter = Net::LDAP::Filter.eq("manager", "uid=evilbacon,ou=People,dc=example,dc=net")
      expect(subject).to receive(:ldap).and_return(ldap)
      expect(logger).to receive(:debug).with(/LDAP Search: filter=.+ base="ou=People,dc=example,dc=net"/)
      expect(logger).to receive(:debug).with(/Completed search: 2 result\(s\)/)
      expect(ldap).to receive(:search).with(
        base: "ou=People,dc=example,dc=net",
        filter: filter,
        attributes: %w[githubdotcomid manager],
        scope: Net::LDAP::SearchScope_WholeSubtree,
        return_result: false
      ).and_yield(entry1).and_yield(entry2)
      allow(entry1).to receive(:dn).and_return(dn1)
      allow(entry2).to receive(:dn).and_return(dn2)

      result = subject.search(
        base: "ou=People,dc=example,dc=net",
        filter: filter,
        attrs: %w[GithubDotComID manager]
      )
      expect(result).to eq(dn1 => entry1, dn2 => entry2)
    end
  end

  describe "#read" do
    it "returns Net::LDAP::Entry if the entry exists" do
      allow(entry1).to receive(:dn).and_return(dn1)
      expect(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:search)
        .with(base: dn1, filter: nil, attributes: "*", scope: Net::LDAP::SearchScope_BaseObject, return_result: false)
        .and_yield(entry1)
      expect(subject.read(dn1)).to eq(entry1)

      # Verifies the cache since `expect` above will error if called more than once
      expect(subject.read(dn1)).to eq(entry1)
    end

    it "returns nil if the entry does not exist" do
      expect(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:search)
        .with(base: dn1, filter: nil, attributes: "*", scope: Net::LDAP::SearchScope_BaseObject, return_result: false)
      expect(subject.read(dn1)).to be nil

      # Verifies the cache since `expect` above will error if called more than once
      expect(subject.read(dn1)).to be nil
    end
  end

  describe "#exists?" do
    it "returns false if the entry does not exist" do
      allow(entry1).to receive(:dn).and_return(dn1)
      expect(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:search)
        .with(base: dn1, filter: nil, attributes: "*", scope: Net::LDAP::SearchScope_BaseObject, return_result: false)
        .and_yield(entry1)
      expect(subject.exists?(dn1)).to eq(true)

    end

    it "returns true if the entry exists" do
      allow(entry1).to receive(:dn).and_return(dn1)
      expect(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:search)
        .with(base: dn1, filter: nil, attributes: "*", scope: Net::LDAP::SearchScope_BaseObject, return_result: false)
      expect(subject.exists?(dn1)).to eq(false)
    end
  end

  describe "#upsert" do
    let(:dn) { "cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net" }
    let(:attributes) { { "eyes" => "green", "breed" => "Russian Blue" } }
    let(:attributes_symkeys) { attributes.map { |k, v| [k.to_sym, v] }.to_h }

    it "calls create when the entry does not exist" do
      expect(subject).to receive(:search).with(base: dn, attrs: "*", scope: 0).and_return({})
      expect(subject).to receive(:create).with(dn: dn, attributes: attributes).and_return(true)
      expect(subject.send(:upsert, dn: dn, attributes: attributes)).to eq(true)
    end

    it "calls update when the entry exists" do
      existing_obj = instance_double(Net::LDAP::Entry)
      allow(existing_obj).to receive(:attribute_names).and_return(attributes_symkeys.keys)
      allow(existing_obj).to receive(:[]) { |arg| attributes_symkeys[arg] }

      expect(subject).to receive(:search).with(base: dn, attrs: "*", scope: 0).and_return({dn => existing_obj})
      expect(subject).to receive(:update).with(dn: dn, existing: existing_obj, attributes: attributes).and_return(true)
      expect(subject.send(:upsert, dn: dn, attributes: attributes)).to eq(true)
    end
  end

  describe "#delete" do
    let(:dn) { "cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net" }
    let(:existing) { instance_double(Net::LDAP::Entry) }

    it "returns true when the entry did not exist to begin with" do
      expect(subject).not_to receive(:ldap)
      expect(subject).to receive(:search).with(base: dn, attrs: "*", scope: 0).and_return({})
      expect(logger).to receive(:debug).with("Not deleting #{dn} because it does not exist")
      expect(subject.delete(dn)).to eq(true)
    end

    it "returns true when the call succeeds" do
      operation_result = { "code" => 0, "message" => ":tada:" }
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(subject).to receive(:search).with(base: dn, attrs: "*", scope: 0).and_return({dn => existing})
      expect(ldap).to receive(:delete).with(dn: dn)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      expect(subject.delete(dn)).to eq(true)
    end

    it "returns false when the call fails" do
      operation_result = { "code" => 1, "message" => ":crying_cat_face:" }
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(subject).to receive(:search).with(base: dn, attrs: "*", scope: 0).and_return({dn => existing})
      expect(ldap).to receive(:delete).with(dn: dn)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      expect(logger).to receive(:error).with(/Error deleting cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net: :crying_cat_face:/)
      expect(subject.delete(dn)).to eq(false)
    end
  end

  describe "#modify" do
    let(:dn) { "uid=kitteh,ou=Felines,ou=People,dc=example,dc=net" }

    it "returns false when there are no updates" do
      result = subject.modify(dn, {})
      expect(result).to eq(false)
    end

    it "returns true when calls succeed" do
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:replace_attribute).with(dn, "eyes", ["green", "blue"]).and_return(true)
      expect(ldap).to receive(:replace_attribute).with(dn, "breed", "Russian Blue").and_return(true)
      expect(ldap).to receive(:delete_attribute).with(dn, "barks").and_return(true)

      result = subject.modify(dn, { "eyes" => ["green", "blue"], "breed" => "Russian Blue", "barks" => nil })
      expect(result).to eq(true)
    end

    it "returns false and logs error when modify attribute fails" do
      operation_result = OpenStruct.new(code: 1, message: ":crying_cat_face:", error_message: "The kitten cries")
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:replace_attribute).with(dn, "eyes", ["green", "blue"]).and_return(true)
      expect(ldap).to receive(:replace_attribute).with(dn, "breed", "Russian Blue").and_return(false)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      expect(logger).to receive(:error).with("Error modifying attribute breed in #{dn}: :crying_cat_face:")
      expect(logger).to receive(:error).with("LDAP code=1: The kitten cries")

      result = subject.modify(dn, { "eyes" => ["green", "blue"], "breed" => "Russian Blue", "barks" => nil })
      expect(result).to eq(false)
    end

    it "returns false and logs error when delete attribute fails" do
      operation_result = OpenStruct.new(code: 1, message: ":crying_cat_face:", error_message: "The kitten cries")
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:replace_attribute).with(dn, "eyes", ["green", "blue"]).and_return(true)
      expect(ldap).to receive(:replace_attribute).with(dn, "breed", "Russian Blue").and_return(true)
      expect(ldap).to receive(:delete_attribute).with(dn, "barks").and_return(false)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      expect(logger).to receive(:error).with("Error deleting attribute barks in #{dn}: :crying_cat_face:")
      expect(logger).to receive(:error).with("LDAP code=1: The kitten cries")

      result = subject.modify(dn, { "eyes" => ["green", "blue"], "breed" => "Russian Blue", "barks" => nil })
      expect(result).to eq(false)
    end
  end

  describe "#create" do
    let(:dn) { "cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net" }
    let(:attributes) { { "eyes" => "green", "breed" => "Russian Blue" } }

    it "returns true when the call succeeds" do
      operation_result = { "code" => 0, "message" => ":tada:" }
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:add).with(dn: dn, attributes: attributes)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      expect(subject.send(:create, dn: dn, attributes: attributes)).to eq(true)
    end

    it "returns false when the call fails" do
      operation_result = { "code" => 1, "message" => ":crying_cat_face:", "error_message" => "The kitten cries" }
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:add).with(dn: dn, attributes: attributes)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      expect(logger).to receive(:error).with("cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net: 1 The kitten cries")
      expect(logger).to receive(:error).with("Error creating cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net ({\"eyes\"=>\"green\", \"breed\"=>\"Russian Blue\"}): :crying_cat_face:")
      expect(subject.send(:create, dn: dn, attributes: attributes)).to eq(false)
    end
  end

  describe "#update" do
    let(:dn) { "cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net" }
    let(:existing) { { eyes: "green", breed: "Russian Blue" } }
    let(:attributes) { { "eyes" => "green", "breed" => "Russian Blue", "food" => "kibble" } }
    let(:operations) { [[:add, :food, "kibble"]] }
    let(:existing_obj) { instance_double(Net::LDAP::Entry) }

    it "returns nil when there are no differences" do
      modified_existing = attributes.map { |k, v| [k.to_sym, v] }.to_h
      allow(existing_obj).to receive(:attribute_names).and_return(modified_existing.keys)
      allow(existing_obj).to receive(:[]) { |arg| modified_existing[arg] }

      expect(subject).not_to receive(:ldap)
      expect(subject.send(:update, dn: dn, existing: existing_obj, attributes: attributes)).to eq(nil)
    end

    it "returns true when the call succeeds" do
      allow(existing_obj).to receive(:attribute_names).and_return(existing.keys)
      allow(existing_obj).to receive(:[]) { |arg| existing[arg] }

      operation_result = { "code" => 0, "message" => ":tada:" }
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:modify).with(dn: dn, operations: operations)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      expect(subject.send(:update, dn: dn, existing: existing_obj, attributes: attributes)).to eq(true)
    end

    it "returns false when the call fails" do
      allow(existing_obj).to receive(:attribute_names).and_return(existing.keys)
      allow(existing_obj).to receive(:[]) { |arg| existing[arg] }

      operation_result = { "code" => 1, "message" => ":crying_cat_face:" }
      allow(subject).to receive(:ldap).and_return(ldap)
      expect(ldap).to receive(:modify).with(dn: dn, operations: operations)
      expect(ldap).to receive(:get_operation_result).and_return(operation_result)
      detail = "[[:add, :food, \"kibble\"]]"
      expect(logger).to receive(:error).with("Error modifying #{dn}: #{detail} :crying_cat_face:")
      expect(subject.send(:update, dn: dn, existing: existing_obj, attributes: attributes)).to eq(false)
    end
  end

  describe "#ops_array" do
    it "returns the expected array" do
      existing = {
        different: "existing",
        identical: ["kittens"],
        ignored: "existing",
        Removed: "existing",
      }

      attributes = {
        "added" => "new",
        "Different" => "new",
        "identical" => "kittens",
        "removed" => nil,
        "removed_too" => nil
      }

      existing_obj = instance_double(Net::LDAP::Entry)
      allow(existing_obj).to receive(:attribute_names).and_return(existing.keys)
      allow(existing_obj).to receive(:[]) { |arg| existing[arg] }

      result = subject.send(:ops_array, existing: existing_obj, attributes: attributes)
      expect(result).to be_a_kind_of(Array)
      expect(result.size).to eq(3)
      expect(result).to include([:add, :added, "new"])
      expect(result).to include([:replace, :different, "new"])
      expect(result).to include([:delete, :removed, nil])
    end

    it "returns an empty array if there are no changes" do
      existing = { foo: "bar" }
      attributes = { "foo" => "bar" }

      existing_obj = instance_double(Net::LDAP::Entry)
      allow(existing_obj).to receive(:attribute_names).and_return(existing.keys)
      allow(existing_obj).to receive(:[]) { |arg| existing[arg] }

      result = subject.send(:ops_array, existing: existing_obj, attributes: attributes)
      expect(result).to eq([])
    end
  end

  describe "#member_array" do
    let(:dn) { "cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net" }
    let(:snowshoe) { Entitlements::Models::Person.new(uid: "snowshoe") }
    let(:russian_blue) { Entitlements::Models::Person.new(uid: "russian_blue") }
    let(:uid_array) { %w[snowshoe russian_blue] }
    let(:dn_array) { uid_array.map { |u| person_dn_format.gsub("%KEY%", u) } }

    it "returns :uniquemember for groupOfUniqueNames" do
      entry = instance_double(Net::LDAP::Entry)
      allow(entry).to receive(:[]).with(:objectclass).and_return(["groupOfUniqueNames"])
      allow(entry).to receive(:[]).with(:uniquemember).and_return(dn_array)
      allow(entry).to receive(:dn).and_return(dn)
      result = described_class.send(:member_array, entry)
      expect(result).to eq(uid_array)
    end

    it "returns :member for groupOfNames" do
      entry = instance_double(Net::LDAP::Entry)
      allow(entry).to receive(:[]).with(:objectclass).and_return(["groupOfNames"])
      allow(entry).to receive(:[]).with(:member).and_return(dn_array)
      allow(entry).to receive(:dn).and_return(dn)
      result = described_class.send(:member_array, entry)
      expect(result).to eq(uid_array)
    end

    it "returns :member for posixGroup" do
      entry = instance_double(Net::LDAP::Entry)
      allow(entry).to receive(:[]).with(:objectclass).and_return(["posixGroup"])
      allow(entry).to receive(:[]).with(:memberuid).and_return(dn_array)
      allow(entry).to receive(:dn).and_return(dn)
      result = described_class.send(:member_array, entry)
      expect(result).to eq(uid_array)
    end

    it "discards the group's own DN if the group is a member of itself" do
      dn_array << dn
      entry = instance_double(Net::LDAP::Entry)
      allow(entry).to receive(:[]).with(:objectclass).and_return(["posixGroup"])
      allow(entry).to receive(:[]).with(:memberuid).and_return(dn_array)
      allow(entry).to receive(:dn).and_return(dn)
      result = described_class.send(:member_array, entry)
      expect(result).to eq(uid_array)
    end

    it "raises error for unknown object class" do
      entry = instance_double(Net::LDAP::Entry)
      allow(entry).to receive(:[]).with(:objectclass).and_return(["basketOfKittens"])
      allow(entry).to receive(:dn).and_return(dn)
      allow(entry).to receive(:dn).and_return(dn)
      expect do
        described_class.send(:member_array, entry)
      end.to raise_error('Do not know how to handle objectClass = ["basketOfKittens"] for dn="cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net"!')
    end
  end
end
