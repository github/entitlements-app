# frozen_string_literal: true

require_relative "../../spec_helper"

describe Entitlements::Util::Override do
  let(:ldap) { instance_double(Entitlements::Service::LDAP) }
  let(:group) { instance_double(Entitlements::Models::Group) }

  describe "#override_hash_from_plugin" do
    it "returns nil when the plugin configuration is nil" do
      result = described_class.override_hash_from_plugin(nil, group, ldap)
      expect(result).to be nil
    end

    it "loads and executes a plugin that is found" do
      config = { "file" => "plugins/dummy_plugin.rb", "class" => "DummyPlugin" }
      result = described_class.override_hash_from_plugin(config, group, ldap)
      expect(result).to eq({"foo" => "bar"})
    end

    it "loads and executes a plugin that is found by absolute path" do
      config = { "file" => File.join(File.dirname(Entitlements.config_file), "plugins/dummy_plugin.rb"), "class" => "DummyPlugin" }
      result = described_class.override_hash_from_plugin(config, group, ldap)
      expect(result).to eq({"foo" => "bar"})
    end

    it "loads and executes a built-in plugin" do
      config = { "file" => "dummy.rb", "class" => "Dummy" }
      result = described_class.override_hash_from_plugin(config, group, ldap)
      expect(result).to eq({})
    end

    it "raises an error if needed parameters are not supplied" do
      config = {"class" => "DummyPlugin"}
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(ArgumentError, "plugin configuration hash must contain 'file' key")

      config = {"file" => "plugins/dummy_plugin.rb"}
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(ArgumentError, "plugin configuration hash must contain 'class' key")
    end

    it "raises an error if the plugin file is not found" do
      config = { "file" => "plugins/no_file.rb", "class" => "NoFile" }
      path = File.dirname(Entitlements.config_file)
      message = "Could not locate plugin for \"plugins/no_file.rb\" at \"#{path}/plugins/no_file.rb\""
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(ArgumentError, message)
    end

    it "raises an error if the plugin cannot be required" do
      config = { "file" => "plugins/bad_ruby.rb", "class" => "BadRuby" }
      path = File.dirname(Entitlements.config_file)
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(SyntaxError, /bad_ruby.rb:1: syntax error, unexpected end-of-input/)
    end

    it "raises an error if the loaded? method does not respond" do
      config = { "file" => "plugins/bad_plugin.rb", "class" => "BadPlugin" }
      path = File.dirname(Entitlements.config_file)
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(ArgumentError, "Plugin Entitlements::Plugins::BadPlugin should inherit Entitlements::Plugins")
    end

    it "raises an error if the override_hash method is unimplemented" do
      config = { "file" => "plugins/bad_plugin_2.rb", "class" => "BadPlugin2" }
      path = File.dirname(Entitlements.config_file)
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(ArgumentError, "Plugin Entitlements::Plugins::BadPlugin2 must implement override_hash method")
    end

    it "passes through an error if the override_hash method is unimplemented in the child class" do
      config = { "file" => "plugins/bad_plugin_3.rb", "class" => "BadPlugin3" }
      path = File.dirname(Entitlements.config_file)
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(RuntimeError, "Please define override_hash in the child class Entitlements::Plugins::BadPlugin3!")
    end

    it "raises an error if the override_hash returns something other than a hash" do
      config = { "file" => "plugins/bad_plugin_4.rb", "class" => "BadPlugin4" }
      path = File.dirname(Entitlements.config_file)
      expect do
        described_class.override_hash_from_plugin(config, group, ldap)
      end.to raise_error(ArgumentError, "Plugin Entitlements::Plugins::BadPlugin4.override_hash must return hash, not Symbol")
    end
  end
end
