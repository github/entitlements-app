# frozen_string_literal: true

# By the time we run this test we have already tested connectivity from the master script. However running
# this basic verification confirms that we can connect to the fake git server, before moving into more complicated tests.

require_relative "spec_helper"
require "base64"
require "open3"
require "tmpdir"

describe Entitlements do
  before(:all) do
    ssh_dir = File.join(ENV["HOME"], ".ssh")
    if File.directory?(ssh_dir)
      raise "Unexpected presence of SSH directory #{ssh_dir}! Are you certain you're running this in Docker?"
    end

    ssh_key = File.join(ssh_dir, "id_rsa")
    FileUtils.mkdir_p ssh_dir
    File.chmod 0700, ssh_dir
    FileUtils.cp ENV["GIT_REPO_SSH_KEY"], ssh_key
    File.chmod 0400, ssh_key
    File.open(File.join(ssh_dir, "config"), "w") do |f|
      f.puts "Host git-server.fake"
      f.puts "  UserKnownHostsFile /dev/null"
      f.puts "  StrictHostKeyChecking no"
    end
    File.chmod 0644, File.join(ssh_dir, "config")

    @tempdir = Dir.mktmpdir
    @stdout, @stderr, @result = Open3.capture3(
      "git clone ssh://git@git-server.fake/git-server/repos/entitlements-audit.git",
      chdir: @tempdir
    )
  end

  after(:all) do
    FileUtils.remove_entry_secure(@tempdir) if File.directory?(@tempdir)
    FileUtils.remove_entry_secure(File.join(ENV["HOME"], ".ssh"))
  end

  it "has the correct stdout" do
    expect(@stdout).to eq("")
  end

  it "has the correct stderr" do
    expect(@stderr).to match(/^Cloning into 'entitlements-audit'...$/)
    expect(@stderr).to match(/^Warning: Permanently added 'git-server.fake/)
  end

  it "has the correct return code" do
    expect(@result.exitstatus).to eq(0)
  end

  it "created the README.md file" do
    expect(File.file?(File.join(@tempdir, "entitlements-audit", "README.md"))).to eq(true)
    expect(File.read(File.join(@tempdir, "entitlements-audit", "README.md"))).to eq("# entitlements-audit Sample Repo\n")
  end
end
