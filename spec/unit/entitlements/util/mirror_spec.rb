# frozen_string_literal: true
require_relative "../../spec_helper"

describe Entitlements::Util::Mirror do
  describe "#validate_mirror!" do
    let(:key) { "entitlements/mirror" }
    let(:path) { File.join(Entitlements.config_path, key) }

    it "raises an error if a directory for the key exists" do
      allow(Entitlements::Util::Util).to receive(:path_for_group).with(key).and_return("..../#{key}")
      expect { described_class.validate_mirror!(key) }.to raise_error(ArgumentError, /declared as a mirror OU but source.+exists/)
    end

    context "when the target does not exist" do
      let(:entitlements_config_file) { fixture("config-files/config-mirror-target-does-not-exist.yaml") }

      it "raises" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(key).and_raise(Errno::ENOENT)
        expect { described_class.validate_mirror!(key) }.to raise_error(ArgumentError, /declared as a mirror to a non-existing target/)
      end
    end

    context "when the target is also a mirror" do
      let(:entitlements_config_file) { fixture("config-files/config-mirror-target-is-also-a-mirror.yaml") }

      it "raises" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(key).and_raise(Errno::ENOENT)
        expect { described_class.validate_mirror!(key) }.to raise_error(ArgumentError, /declared as a mirror to a mirror target/)
      end
    end

    context "when the configuration is valid" do
      let(:entitlements_config_file) { fixture("config-files/config-mirror-valid.yaml") }

      it "returns" do
        allow(Entitlements::Util::Util).to receive(:path_for_group).with(key).and_raise(Errno::ENOENT)
        expect { described_class.validate_mirror!(key) }.not_to raise_error
      end
    end
  end
end
