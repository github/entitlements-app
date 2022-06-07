# frozen_string_literal: true
require_relative "../../spec_helper"

describe Entitlements::Util::Util do
  describe "#downcase_first_attribute" do
    it "returns a properly formatted DN with a downcased first attribute" do
      result = described_class.downcase_first_attribute("uid=MAINECOON,ou=People,dc=kittens,dc=net")
      expect(result).to eq("uid=mainecoon,ou=People,dc=kittens,dc=net")
    end

    it "just returns the input value, downcased, when unparseable" do
      result = described_class.downcase_first_attribute("MAINECOON;People;github;net")
      expect(result).to eq("mainecoon;people;github;net")
    end
  end

  describe "#first_attr" do
    it "returns the string if it does not match the pattern for a DN" do
      result = described_class.first_attr("MAINECOON;People;github;net")
      expect(result).to eq("MAINECOON;People;github;net")
    end

    it "returns the first attribute if it matches the pattern for a DN" do
      result = described_class.first_attr("uid=MAINECOON,ou=People,dc=kittens,dc=net")
      expect(result).to eq("MAINECOON")
    end
  end

  describe "#validate_attr!" do
    let(:spec) do
      {
        "foo" => { required: true, type: String },
        "bar" => { required: false, type: Symbol }
      }
    end

    it "raises when a required key is missing" do
      data = { "bar" => :foo }
      expect do
        described_class.validate_attr!(spec, data, "rspec")
      end.to raise_error(RuntimeError, "rspec is missing attribute foo!")
    end

    it "raises when a required key has the wrong data type" do
      data = { "foo" => 123, "bar" => :foo }
      expect do
        described_class.validate_attr!(spec, data, "rspec")
      end.to raise_error(RuntimeError, 'rspec attribute "foo" is supposed to be String, not Integer!')
    end

    it "raises when a non-required key has the wrong data type" do
      data = { "foo" => "xyz", "bar" => 123 }
      expect do
        described_class.validate_attr!(spec, data, "rspec")
      end.to raise_error(RuntimeError, 'rspec attribute "bar" is supposed to be Symbol, not Integer!')
    end

    it "raises when there are unknown keys" do
      data = { "foo" => "xyz", "bar" => :baz, "fizz" => "buzz" }
      expect do
        described_class.validate_attr!(spec, data, "rspec")
      end.to raise_error(RuntimeError, "rspec contains unknown attribute(s): fizz")
    end

    it "does not raise when the hash matches the spec" do
      data = { "foo" => "xyz", "bar" => :baz }
      expect do
        described_class.validate_attr!(spec, data, "rspec")
      end.not_to raise_error
    end

    it "does not raise when the hash matches the spec" do
      data = { "foo" => "xyz" }
      expect do
        described_class.validate_attr!(spec, data, "rspec")
      end.not_to raise_error
    end

    context "with an array of acceptable types" do
      let(:spec) do
        {
          "foo" => { required: true, type: [String, Symbol] },
          "bar" => { required: false, type: Symbol }
        }
      end

      it "raises with no match" do
        data = { "foo" => 123 }
        expect do
          described_class.validate_attr!(spec, data, "rspec")
        end.to raise_error(RuntimeError, 'rspec attribute "foo" is supposed to be [String, Symbol], not Integer!')
      end

      it "does not raise with a match" do
        data = { "foo" => :xyz }
        expect do
          described_class.validate_attr!(spec, data, "rspec")
        end.not_to raise_error
      end
    end
  end

  describe "#path_for_group" do
    let(:key) { "foo/bar" }

    context "when called with a group not defined in the configuration" do
      let(:entitlements_config_hash) { { "groups" => {} } }

      it "raises" do
        expect do
          described_class.path_for_group(key)
        end.to raise_error(ArgumentError, 'path_for_group: Group "foo/bar" is not defined in the entitlements configuration!')
      end
    end

    context "when no dir is defined" do
      let(:entitlements_config_hash) { { "configuration_path" => "/bar", "groups" => { key => {} } } }

      it "returns the entitlements path + group key" do
        allow(File).to receive(:directory?).with("/bar/foo/bar").and_return(true)
        expect(described_class.path_for_group(key)).to eq("/bar/foo/bar")
      end
    end

    context "when the dir starts with /" do
      let(:entitlements_config_hash) { { "configuration_path" => "/bar", "groups" => { key => { "dir" => "/baz/fizz" } } } }

      it "returns the absolute dir" do
        allow(File).to receive(:directory?).with("/baz/fizz").and_return(true)
        expect(described_class.path_for_group(key)).to eq("/baz/fizz")
      end
    end

    context "when the dir does not start with /" do
      let(:entitlements_config_hash) { { "configuration_path" => "/bar/buzz", "groups" => { key => { "dir" => "../baz/fizz" } } } }

      it "returns the relative dir" do
        allow(File).to receive(:directory?).with("/bar/baz/fizz").and_return(true)
        expect(described_class.path_for_group(key)).to eq("/bar/baz/fizz")
      end
    end

    context "when the target directory does not exist" do
      let(:entitlements_config_hash) { { "configuration_path" => "/bar", "groups" => { key => {} } } }

      it "raises" do
        allow(File).to receive(:directory?).with("/bar/foo/bar").and_return(false)
        expect do
          described_class.path_for_group(key)
        end.to raise_error(Errno::ENOENT, 'No such file or directory - Non-existing directory "/bar/foo/bar" for group "foo/bar"!')
      end
    end
  end

  describe "#any_to_cn" do
    it "returns the common name from a DN string" do
      result = described_class.any_to_cn("cn=kittens,ou=foo,dc=example,dc=net")
      expect(result).to eq("kittens")
    end

    it "returns the common name of a group object" do
      group = Entitlements::Models::Group.new(
        dn: "cn=diff-cats,ou=Github,dc=github,dc=fake",
        members: Set.new
      )
      result = described_class.any_to_cn(group)
      expect(result).to eq("diff-cats")
    end

    it "returns a string as-is when not formatted as a DN" do
      result = described_class.any_to_cn("kittens")
      expect(result).to eq("kittens")
    end

    it "raises for an unknown data type" do
      expect { described_class.any_to_cn(:foo) }.to raise_error(ArgumentError, "Could not determine a common name from :foo!")
    end
  end

  describe "#remove_uids" do
    it "removes matching UIDs in multiple formats" do
      obj = %w[bob uid=Bob,ou=People,dc=kittens,dc=net Tom uid=tom,ou=people,dc=kittens,dc=net emmy]
      uids = Set.new(%w[bob tom])
      Entitlements::Util::Util.remove_uids(obj, uids)
      expect(obj).to eq(%w[emmy])
    end
  end

  describe "#camelize" do
    it "returns the correct string" do
      result = described_class.camelize("hot_chicken_yum")
      expect(result).to eq("HotChickenYum")
    end

    it "capitalizes GitHub" do
      result = described_class.camelize("github_kittens")
      expect(result).to eq("GitHubKittens")
    end

    it "capitalizes LDAP" do
      result = described_class.camelize("github_ldap_kittens")
      expect(result).to eq("GitHubLDAPKittens")
    end
  end

  describe "#decamelize" do
    it "returns the correct string" do
      result = described_class.decamelize("HotChiCkenyum")
      expect(result).to eq("hot_chi_ckenyum")
    end

    it "capitalizes GitHub" do
      result = described_class.decamelize("GitHubKittens")
      expect(result).to eq("github_kittens")
    end

    it "capitalizes LDAP" do
      result = described_class.decamelize("GitHubLDAPKittens")
      expect(result).to eq("github_ldap_kittens")
    end
  end

  describe "#parse_date" do
    context "with a Date object" do
      let(:input) { Date.new(2017, 4, 1) }

      it "returns that Date object" do
        expect(described_class.parse_date(input)).to eq(input)
      end
    end

    context "with a String that looks like a date" do
      let(:input) { "2017-04-01" }

      it "builds and returns a Date object" do
        result = described_class.parse_date(input)
        expect(result).to be_a_kind_of(Date)
        expect(result.month).to eq(4)
        expect(result.day).to eq(1)
        expect(result.year).to eq(2017)
      end
    end

    context "with unrecognized string format" do
      let(:input) { "kittens" }

      it "rejects with error" do
        expect do
          described_class.parse_date(input)
        end.to raise_error(ArgumentError, 'Unsupported date format "kittens" for parse_date!')
      end
    end

    context "with unrecognized object type" do
      let(:input) { :kittens }

      it "rejects with error" do
        expect do
          described_class.parse_date(input)
        end.to raise_error(ArgumentError, "Unsupported object :kittens for parse_date!")
      end
    end
  end

  describe ".dns_for_ou" do
    let(:ou) { "ou=teams,ou=github,dn=github,dn=net" }
    let(:config) { { "base" => "dn=github,dn=net" } }

    it "lists filenames without extensions in the relevant folder" do
      allow(described_class).to receive(:path_for_group).with(ou).and_return("/tmp")
      allow(File).to receive(:directory?).with(anything).and_return(false)
      allow(File).to receive(:directory?).with("/tmp/subfolder/").and_return(true)
      allow(Dir).to receive(:glob).with("/tmp/*").and_return(%w[/tmp/kittens.txt /tmp/cats.txt /tmp/subfolder/ /tmp/README.md])

      dns = described_class.dns_for_ou(ou, config)

      expect(dns).to eq(%w[cn=kittens,dn=github,dn=net cn=cats,dn=github,dn=net])
    end

    it "is picky about file extensions" do
      allow(described_class).to receive(:path_for_group).with(ou).and_return("/tmp")
      allow(File).to receive(:directory?).with(anything).and_return(false)
      allow(Dir).to receive(:glob).with("/tmp/*").and_return(%w[/tmp/illegal$kittens.txt])

      expect do
        described_class.dns_for_ou(ou, config)
      end.to raise_error("Illegal LDAP group name \"illegal$kittens\" in #{ou}!")
    end
  end
end
