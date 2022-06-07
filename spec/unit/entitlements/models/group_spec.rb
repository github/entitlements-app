# frozen_string_literal: true
require_relative "../../spec_helper"

describe Entitlements::Models::Group do
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:dn) { "cn=snowshoe,ou=Felines,ou=Groups,dc=kittens,dc=net" }
  let(:user1) { people_obj.read("blackmanx") }
  let(:user2) { people_obj.read("russianblue") }
  let(:user3) { people_obj.read("nebelung") }
  let(:user4) { people_obj.read("ojosazules") }
  let(:user_array) { [user1, user2].map { |i| i.uid } }

  describe "#copy_of" do
    let(:members) { Set.new([user1, user2]) }

    it "returns an Entitlements::Models::Group with same settings but a different DN" do
      new_dn = "cn=snowshoe,ou=Mirrors,ou=Groups,dc=kittens,dc=net"
      subject = described_class.new(dn: dn, members: members, description: "Fluffy", metadata: { "foo" => "bar" })
      result = subject.copy_of(new_dn)
      expect(result.dn).to eq(new_dn)
      expect(result.description).to eq("Fluffy")
      expect(result.members).to eq(members)
      expect(result.metadata).to eq({ "foo" => "bar" })
    end
  end

  describe "#description" do
    let(:members) { Set.new([user1, user2]) }

    it "returns the cn when description is nil" do
      subject = described_class.new(dn: dn, members: members)
      expect(subject.description).to eq("snowshoe")
    end

    it "returns the cn when description is empty" do
      subject = described_class.new(dn: dn, members: members, description: "")
      expect(subject.description).to eq("snowshoe")
    end

    it "returns the description" do
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.description).to eq(":smile_cat:")
    end
  end

  describe "#members" do
    it "returns a set of people when people are passed in" do
      members = Set.new([user1, user2])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.members).to eq(members)
    end

    it "skips a string entry when people_obj is not passed in" do
      members = Set.new([user1, user2.uid])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      result = subject.members
      expect(result).to be_a_kind_of(Set)
      expect(result.size).to eq(1)
      expect(result.first.uid).to eq(user1.uid)
    end

    it "looks up people from the people hash when user IDs are passed in" do
      members = Set.new([user1.uid, user2.uid])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      result = subject.members(people_obj: people_obj)
      expect(result).to be_a_kind_of(Set)
      expect(result.size).to eq(2)
      expect(result.map { |i| i.uid }.sort).to eq(user_array)
    end

    it "returns an empty set if there are no members in the group due to missing member DN" do
      members = Set.new(["uid=abyssinian,ou=Alumni,dc=kittens,dc=net"])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.members(people_obj: people_obj)).to eq(Set.new)
    end

    it "returns an empty set if there are no members in the group" do
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:")
      expect(subject.members(people_obj: people_obj)).to eq(Set.new)
    end

    it "raises an error if there are no members in the group (with metadata)" do
      m = { "no_members_ok" => "false" }
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:", metadata: m)
      expect { subject.members }.to raise_error(Entitlements::Models::Group::NoMembers)
    end

    it "returns an empty set if there are no members in the group and metadata says it's OK (boolean)" do
      m = { "no_members_ok" => true }
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:", metadata: m)
      expect(subject.members).to eq(Set.new)
    end

    it "returns an empty set if there are no members in the group and metadata says it's OK (string)" do
      m = { "no_members_ok" => "true" }
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:", metadata: m)
      expect(subject.members).to eq(Set.new)
    end
  end

  describe "#member_strings" do
    it "converts people to DN strings" do
      members = Set.new([user1, user2])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.member_strings.to_a).to eq(user_array)
    end

    it "leaves strings alone" do
      members = Set.new([user1.uid, user2.uid])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.member_strings.to_a).to eq(user_array)
    end

    it "returns an empty set if there are no members in the group" do
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:")
      expect(subject.member_strings).to eq(Set.new)
    end

    it "raises an error if there are no members in the group (with metadata)" do
      m = { "no_members_ok" => "false" }
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:", metadata: m)
      expect { subject.member_strings }.to raise_error(Entitlements::Models::Group::NoMembers)
    end

    it "returns an empty set if there are no members in the group and metadata says it's OK (boolean)" do
      m = { "no_members_ok" => true }
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:", metadata: m)
      expect(subject.member_strings).to eq(Set.new)
    end

    it "returns an empty set if there are no members in the group and metadata says it's OK (string)" do
      m = { "no_members_ok" => "true" }
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:", metadata: m)
      expect(subject.member_strings).to eq(Set.new)
    end

    it "does not downcase" do
      subject = described_class.new(dn: dn, members: Set.new([user3, user4]), description: ":smile_cat:")
      expect(subject.member_strings).to eq(Set.new([user3.uid, user4.uid]))
    end
  end

  describe "#member_strings_insensitive" do
    it "downcases the first attribute in each member string" do
      subject = described_class.new(dn: dn, members: Set.new([user3, user4]), description: ":smile_cat:")
      answer = %w[nebelung ojosazules]
      expect(subject.member_strings_insensitive).to eq(Set.new(answer))
    end
  end

  describe "#member?" do
    it "passes the call to the underlying object as objects" do
      members = Set.new([user1])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.member?(user1)).to eq(true)
      expect(subject.member?(user2)).to eq(false)
      expect(subject.member?(user1.uid)).to eq(true)
      expect(subject.member?(user2.uid)).to eq(false)
    end

    it "passes the call to the underlying object as strings" do
      members = Set.new([user1.uid])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.member?(user1)).to eq(true)
      expect(subject.member?(user2)).to eq(false)
      expect(subject.member?(user1.uid)).to eq(true)
      expect(subject.member?(user2.uid)).to eq(false)
    end

    it "implements case-insensitivity of user attribute" do
      members = Set.new(%w[BlAcKmAnX])
      subject = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(subject.member?("blackmanx")).to eq(true)
      expect(subject.member?("BlackManx")).to eq(true)
      expect(subject.member?("BLACKMANX")).to eq(true)
      expect(subject.member?("RAGAMUFFIn")).to eq(false)
    end
  end

  describe "#cn" do
    it "returns the cn determined from the dn" do
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:")
      expect(subject.cn).to eq("snowshoe")
    end

    it "raises an error when the dn cannot be parsed" do
      fake_dn = "wtf=snowshoe,ou=Felines,ou=Groups,dc=kittens,dc=net"
      subject = described_class.new(dn: fake_dn, members: Set.new, description: ":smile_cat:")
      expect { subject.cn }.to raise_error(RuntimeError, "Could not determine CN from group DN #{fake_dn.inspect}!")
    end
  end

  describe "#metadata" do
    it "returns metadata supplied when the group was constructed" do
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:", metadata: { "foo" => "bar" })
      expect(subject.metadata).to eq({ "foo" => "bar" })
    end

    it "raises a custom error if no metadata was supplied" do
      subject = described_class.new(dn: dn, members: Set.new, description: ":smile_cat:")
      expect { subject.metadata }.to raise_error(Entitlements::Models::Group::NoMetadata)
    end
  end

  describe "#equals?" do
    let(:members) { Set.new([user1, user2]) }
    let(:this_obj) { described_class.new(dn: dn, members: members, description: ":smile_cat:") }

    it "returns false when the DN does not match" do
      other_obj = described_class.new(dn: "cn=foobaz", members: members, description: ":smile_cat:")
      expect(this_obj.equals?(other_obj)).to eq(false)
      expect(other_obj.equals?(this_obj)).to eq(false)
    end

    it "returns false when the description does not match" do
      other_obj = described_class.new(dn: dn, members: members, description: ":crying_cat_face:")
      expect(this_obj.equals?(other_obj)).to eq(false)
      expect(other_obj.equals?(this_obj)).to eq(false)
    end

    it "returns false when the member_strings does not match" do
      other_obj = described_class.new(dn: dn, members: Set.new([user1]), description: ":smile_cat:")
      expect(this_obj.equals?(other_obj)).to eq(false)
      expect(other_obj.equals?(this_obj)).to eq(false)
    end

    it "returns true when the attributes match" do
      other_obj = described_class.new(dn: dn, members: members, description: ":smile_cat:")
      expect(this_obj.equals?(other_obj)).to eq(true)
      expect(other_obj.equals?(this_obj)).to eq(true)
    end
  end

  describe "#add_member" do
    let(:members) { Set.new([user1, user2]) }
    subject { described_class.new(dn: dn, members: members, description: "Fluffy") }

    it "adds an Entitlements::Models::Person object as a member" do
      result1 = subject.member_strings
      expect(result1).to eq(Set.new(user_array))

      subject.add_member(user3)
      subject.add_member(user4)

      result2 = subject.member_strings
      expect(result2).to eq(Set.new(user_array + [user3.uid, user4.uid]))
    end
  end

  describe "#remove_member" do
    let(:members) { Set.new([user1, user2]) }
    subject { described_class.new(dn: dn, members: members, description: "Fluffy") }

    it "removes an Entitlements::Models::Person object as a member" do
      result1 = subject.member_strings
      expect(result1).to eq(Set.new(user_array))

      subject.remove_member(user3)
      subject.remove_member(user2)

      result2 = subject.member_strings
      expect(result2).to eq(Set.new([user1.uid]))
    end

    it "removes a distinguished name as a member" do
      result1 = subject.member_strings
      expect(result1).to eq(Set.new(user_array))

      subject.remove_member(user3.uid)
      subject.remove_member(user2.uid)

      result2 = subject.member_strings
      expect(result2).to eq(Set.new([user1.uid]))
    end

    context "with members stored internally as distinguished names" do
      let(:members) { Set.new([user1.uid, user2.uid]) }

      it "removes an Entitlements::Models::Person object as a member" do
        result1 = subject.member_strings
        expect(result1).to eq(Set.new(user_array))

        subject.remove_member(user3)
        subject.remove_member(user2)

        result2 = subject.member_strings
        expect(result2).to eq(Set.new([user1.uid]))
      end

      it "removes a distinguished name as a member" do
        result1 = subject.member_strings
        expect(result1).to eq(Set.new(user_array))

        subject.remove_member(user3.uid)
        subject.remove_member(user2.uid)

        result2 = subject.member_strings
        expect(result2).to eq(Set.new([user1.uid]))
      end
    end
  end

  describe "#update_case" do
    let(:members) { Set.new([user1, user2]) }
    subject { described_class.new(dn: dn, members: members, description: "Fluffy") }

    it "returns false when the given person is not a member" do
      expect(subject).not_to receive(:add_member)
      expect(subject).not_to receive(:remove_member)
      expect(subject.update_case(user3)).to eq(false)
    end

    it "returns false when the capitalization of the person matches" do
      expect(subject).not_to receive(:add_member)
      expect(subject).not_to receive(:remove_member)
      expect(subject.update_case(user2)).to eq(false)
    end

    it "returns true and adds/removes the member when the capitalization differs" do
      expect(subject).to receive(:add_member).with("BlackManx")
      expect(subject).to receive(:remove_member).with("BlackManx")
      expect(subject.update_case("BlackManx")).to eq(true)
    end
  end

  describe "#any_to_uid" do
    subject { described_class.new(dn: dn, members: Set.new, description: ":smile_cat:") }

    it "extracts UID from a string" do
      result = subject.send(:any_to_uid, user1.uid)
      expect(result).to eq(user1.uid)
    end

    it "extracts UID from an Entitlements::Models::Person" do
      result = subject.send(:any_to_uid, user1)
      expect(result).to eq(user1.uid)
    end

    it "raises if a UID cannot be extracted" do
      expect { subject.send(:any_to_uid, :kittens) }.to raise_error(ArgumentError)
    end
  end
end
