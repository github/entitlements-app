# frozen_string_literal: true
require_relative "../../../spec_helper"

describe Entitlements::Data::Groups::Calculated do
  let(:dn) { "cn=kittens,ou=Felines,ou=Groups,dc=example,dc=net" }
  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj, file_objects: {} } }
  let(:blackmanx) { "blackmanx" }
  let(:ragamuffin) { "RAGAMUFFIn" }
  let(:russianblue) { "russianblue" }
  let(:mainecoon) { "mainecoon" }

  describe "#read" do
    it "returns cached value if one exists" do
      fake_group = instance_double(Entitlements::Models::Group)
      described_class.instance_variable_set("@groups_cache", { dn => fake_group })
      expect(described_class.read(dn)).to eq(fake_group)
    end

    it "raises an error if value does not exist in cache" do
      described_class.instance_variable_set("@groups_cache", {})
      expect { described_class.read(dn) }.to raise_error(RuntimeError)
    end
  end

  describe "#read_all" do
    let(:ou_key) { "simple" }
    let(:cfg_obj) { { "base" => "ou=Felines,ou=Groups,dc=example,dc=net" } }

    it "populates the hash from all groups in the directory" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key)
        .and_return(fixture("ldap-config/#{ou_key}"))
      result = described_class.read_all(ou_key, cfg_obj)
      expect(result).to eq(Set.new(%w[simple1 simple2].map { |i| "cn=#{i},#{cfg_obj['base']}" }))
    end

    it "populates the group cache with each DN calculated along the way" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key)
        .and_return(fixture("ldap-config/#{ou_key}"))
      described_class.read_all(ou_key, cfg_obj)
      result = described_class.instance_variable_get("@groups_cache")
      expect(result).to be_a_kind_of(Hash)
      expect(result.keys.sort).to eq(["cn=simple1,#{cfg_obj['base']}", "cn=simple2,#{cfg_obj['base']}"])
      simple1 = result["cn=simple1,#{cfg_obj['base']}"]
      expect(simple1).to be_a_kind_of(Entitlements::Models::Group)
      expect(simple1.description).to eq("simple1")
      expect(simple1.dn).to eq("cn=simple1,#{cfg_obj['base']}")
      expect(simple1.members).to be_a_kind_of(Set)
      expect(simple1.members.map { |i| i.uid }).to include(blackmanx)
      expect(simple1.members.map { |i| i.uid }).to include(ragamuffin)
    end

    it "skips over a subdirectory in the main OU" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("nested_ou")
        .and_return(fixture("ldap-config/nested_ou"))
      answer = Set.new([
        "cn=example1,ou=Felines,ou=Groups,dc=example,dc=net",
        "cn=example2,ou=Felines,ou=Groups,dc=example,dc=net"
      ])
      result = described_class.read_all("nested_ou", cfg_obj)
      expect(result).to eq(answer)
    end

    it "skips an ignored file" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("ignored_file")
        .and_return(fixture("ldap-config/ignored_file"))
      answer = Set.new([
        "cn=example1,ou=Felines,ou=Groups,dc=example,dc=net",
        "cn=example2,ou=Felines,ou=Groups,dc=example,dc=net"
      ])
      result = described_class.read_all("ignored_file", cfg_obj)
      expect(result).to eq(answer)
    end

    it "handles a slash in ou_key and descends into a subdirectory" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("nested_ou/sub_ou")
        .and_return(fixture("ldap-config/nested_ou/sub_ou"))
      cfg_obj = { "base" => "ou=sub_ou,ou=Felines,ou=Groups,dc=example,dc=net" }
      answer = Set.new([
        "cn=subexample,ou=sub_ou,ou=Felines,ou=Groups,dc=example,dc=net"
      ])
      result = described_class.read_all("nested_ou/sub_ou", cfg_obj)
      expect(result).to eq(answer)
    end

    it "raises an error if an illegal filename is encountered" do
      path = File.join(Entitlements.config_path, ou_key)
      allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key)
        .and_return(fixture("ldap-config/#{ou_key}"))
      allow(Dir).to receive(:glob).with(File.join(path, "*")).and_return([File.join(path, "abcd!efg")])
      expect { described_class.read_all(ou_key, cfg_obj) }.to raise_error("Illegal LDAP group name \"abcd!efg\" in simple!")
    end

    context "with broken references" do
      let(:ou_key) { "missing_references_2" }

      it "raises an error if there is a broken reference" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key)
          .and_return(fixture("ldap-config/#{ou_key}"))
        expect do
          described_class.read_all(ou_key, cfg_obj)
        end.to raise_error(%r{Could not find a configuration for .+/missing_references_2/group4.\(rb\|txt\|yaml\)})
      end

      it "does not raise an error if there is a broken reference but skip_broken_references is set" do
        Entitlements.config_file = fixture("config.yaml")
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(ou_key)
          .and_return(fixture("ldap-config/#{ou_key}"))
        answer = Set.new(["cn=group3,ou=Felines,ou=Groups,dc=example,dc=net"])
        expect(described_class.read_all(ou_key, cfg_obj, skip_broken_references: true)).to eq(answer)
      end

      it "raises an error if an invalid directory is specified" do
        Entitlements.config_file = fixture("config.yaml")
        expect do
          described_class.read_all("aldfkdflakjalsdfkj", cfg_obj)
        end.to raise_error(%r{Non-existing directory})
      end
    end
  end

  describe "#read_mirror" do
    it "raises an exception if read_all has not been called on the source OU" do
      expect do
        described_class.send(:read_mirror, "foo", { "mirror" => "bar" })
      end.to raise_error(RuntimeError, /Cannot read_mirror on "foo" because read_all/)
    end

    it "raises an exception if a source group has not been calculated" do
      groups_in_ou_cache = { "bar" => Set.new(%w[fizz buzz].map { |i| "cn=#{i},ou=Groups,dc=example,dc=net" }) }
      described_class.instance_variable_set("@groups_in_ou_cache", groups_in_ou_cache)
      expect do
        described_class.send(:read_mirror, "foo", { "mirror" => "bar" })
      end.to raise_error(RuntimeError, 'No group has been calculated for "cn=fizz,ou=Groups,dc=example,dc=net"!')
    end

    it "returns a set of DNs and populates the cache correctly" do
      fizz = instance_double(Entitlements::Models::Group)
      fizz_copy = instance_double(Entitlements::Models::Group)
      allow(fizz).to receive(:cn).and_return("fizz")
      allow(fizz).to receive(:copy_of).with("cn=fizz,ou=Mirrors,dc=example,dc=net").and_return(fizz_copy)

      buzz = instance_double(Entitlements::Models::Group)
      buzz_copy = instance_double(Entitlements::Models::Group)
      allow(buzz).to receive(:cn).and_return("buzz")
      allow(buzz).to receive(:copy_of).with("cn=buzz,ou=Mirrors,dc=example,dc=net").and_return(buzz_copy)

      groups_in_ou_cache = { "bar" => Set.new(%w[fizz buzz].map { |i| "cn=#{i},ou=Groups,dc=example,dc=net" }) }
      groups_cache = {
        "cn=fizz,ou=Groups,dc=example,dc=net" => fizz,
        "cn=buzz,ou=Groups,dc=example,dc=net" => buzz,
      }
      described_class.instance_variable_set("@groups_in_ou_cache", groups_in_ou_cache)
      described_class.instance_variable_set("@groups_cache", groups_cache)
      result = described_class.send(:read_mirror, "foo", { "mirror" => "bar", "base" => "ou=Mirrors,dc=example,dc=net" })
      expect(result).to eq(Set.new(["cn=fizz,ou=Mirrors,dc=example,dc=net", "cn=buzz,ou=Mirrors,dc=example,dc=net"]))
    end
  end

  describe "#all_groups" do
    let(:cfg_obj_1) { { "base" => "ou=Felines,ou=Groups,dc=example,dc=net" } }
    let(:cfg_obj_2) { { "base" => "ou=Felines2,ou=Groups,dc=example,dc=net" } }
    let(:cfg_obj_3) { { "mirror" => "simple2" } }

    it "returns the hash of all OUs and their configs and groups" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("simple")
        .and_return(fixture("ldap-config/simple"))
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("simple2")
        .and_return(fixture("ldap-config/simple2"))
      allow(Entitlements::Util::Util).to receive(:path_for_group).with("simple3")
        .and_return(fixture("ldap-config/simple3"))

      described_class.read_all("simple", cfg_obj_1)
      described_class.read_all("simple2", cfg_obj_2)
      described_class.read_all("simple3", cfg_obj_3)

      result = described_class.all_groups
      expect(result).to be_a_kind_of(Hash)
      expect(result.keys).to eq(%w[simple simple2])

      expect(result["simple"][:config]).to eq(cfg_obj_1)
      expect(result["simple"][:groups]).to be_a_kind_of(Hash)
      expect(result["simple"][:groups].keys.size).to eq(2)

      member_strings_1a = [ragamuffin, blackmanx]
      expect(result["simple"][:groups]["cn=simple1,ou=Felines,ou=Groups,dc=example,dc=net"].member_strings).to eq(Set.new(member_strings_1a))

      member_strings_2a = [russianblue]
      expect(result["simple"][:groups]["cn=simple2,ou=Felines,ou=Groups,dc=example,dc=net"].member_strings).to eq(Set.new(member_strings_2a))

      expect(result["simple2"][:config]).to eq(cfg_obj_2)
      expect(result["simple2"][:groups]).to be_a_kind_of(Hash)
      expect(result["simple2"][:groups].keys.size).to eq(2)

      member_strings_1b = [ragamuffin, blackmanx]
      expect(result["simple2"][:groups]["cn=simple1,ou=Felines2,ou=Groups,dc=example,dc=net"].member_strings).to eq(Set.new(member_strings_1b))

      member_strings_2b = [mainecoon]
      expect(result["simple2"][:groups]["cn=simple2,ou=Felines2,ou=Groups,dc=example,dc=net"].member_strings).to eq(Set.new(member_strings_2b))
    end
  end

  describe "#ruleset" do
    it "raises an exception when the extension cannot be determined" do
      filename = File.join(Entitlements.config_path, "simple", "foobar")
      expect do
        described_class.send(:ruleset, filename: filename, config: {"allowed_types" => %w[txt yaml]})
      end.to raise_error(ArgumentError, /Unable to determine the extension on ".+\/foobar"!/)
    end

    it "raises an exception when allowed_types is not an array" do
      filename = File.join(Entitlements.config_path, "simple", "foobar.txt")
      expect do
        described_class.send(:ruleset, filename: filename, config: {"allowed_types" => :kittens})
      end.to raise_error(ArgumentError, /Configuration error: allowed_types should be an Array, got Symbol!/)
    end

    it "refuses a Ruby ruleset for a .rb file when disabled in the configuration" do
      filename = File.join(Entitlements.config_path, "simple", "foobar.rb")
      expect do
        described_class.send(:ruleset, filename: filename, config: {"allowed_types" => %w[txt yaml]})
      end.to raise_error(ArgumentError, /Files with extension "rb" are not allowed in this OU! Allowed: txt,yaml!/)
    end

    it "refuses a YAML ruleset for a .yaml file when disabled in the configuration" do
      filename = File.join(Entitlements.config_path, "simple", "foobar.yaml")
      expect do
        described_class.send(:ruleset, filename: filename, config: {"allowed_types" => %w[txt]})
      end.to raise_error(ArgumentError, /Files with extension "yaml" are not allowed in this OU! Allowed: txt!/)
    end

    it "invokes Ruby ruleset for a .rb file" do
      filename = File.join(Entitlements.config_path, "metadata", "good.rb")
      result = described_class.send(:ruleset, filename: filename, config: {})
      expect(result).to be_a_kind_of(Entitlements::Data::Groups::Calculated::Ruby)
    end

    it "invokes text ruleset for a .txt file" do
      filename = File.join(Entitlements.config_path, "text", "example.txt")
      result = described_class.send(:ruleset, filename: filename, config: {})
      expect(result).to be_a_kind_of(Entitlements::Data::Groups::Calculated::Text)
    end

    it "invokes YAML ruleset for a .yaml file" do
      filename = File.join(Entitlements.config_path, "simple", "simple1.yaml")
      result = described_class.send(:ruleset, filename: filename, config: {})
      expect(result).to be_a_kind_of(Entitlements::Data::Groups::Calculated::YAML)
    end

    it "raises an error for an unknown file" do
      filename = File.join(Entitlements.config_path, "simple", "virus.exe")
      expect do
        described_class.send(:ruleset, filename: filename, config: {})
      end.to raise_error(ArgumentError, /Unable to map filename ".+virus.exe" to a ruleset object!/)
    end
  end
end
