# frozen_string_literal: true

require_relative "../spec_helper"

# NOTE: Most methods in this class are already tested end-to-end by virtue of loading
# extras for other tests. For example the extras/orgchart module loads that system and
# registers and tests rules.

describe Entitlements::Extras do
  describe "#load_extra" do
    it "raises if base.rb cannot be found in the extra's configured directory" do
      expect(File).to receive(:file?).with("/tmp/foo/myextra/base.rb").and_return(false)
      expect do
        described_class.load_extra("myextra", "/tmp/foo")
      end.to raise_error(Errno::ENOENT, "No such file or directory - Error loading myextra: There is no file `base.rb` in directory `/tmp/foo/myextra`.")
    end

    it "raises if base.rb cannot be found in the default extras directory" do
      extra_dir = File.expand_path("../../../lib/entitlements/extras", __dir__)
      expect(File).to receive(:file?).with("#{extra_dir}/myextra/base.rb").and_return(false)
      expect do
        described_class.load_extra("myextra")
      end.to raise_error(Errno::ENOENT, "No such file or directory - Error loading myextra: There is no file `base.rb` in directory `#{extra_dir}/myextra`.")
    end
  end
end
