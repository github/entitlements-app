# frozen_string_literal: true

require "base64"
require "logger"
require "net/http"
require "net/ldap"
require "ostruct"
require "open3"
require "rugged"
require "shellwords"
require "set"
require "stringio"
require "tmpdir"
require "uri"

require "rspec"
require "rspec/support"
require "rspec/support/object_formatter"

require_relative "../../../lib/entitlements"

RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = 100000

ENV["LDAP_URI"] = "ldaps://ldap-server.fake:636"
ENV["LDAP_BINDDN"] = "uid=emmy,ou=Service_Accounts,dc=kittens,dc=net"
ENV["LDAP_BINDPW"] = "kittens"

RSpec.configure do |config|
  config.before(:suite) do
    ENV["ENTITLEMENTS_ACCEPTANCE_GIT_CHECKOUT_BASE"] = Dir.mktmpdir

    # SSH key
    ENV["GIT_REPO_SSH_KEY"] = File.join(ENV["ENTITLEMENTS_ACCEPTANCE_GIT_CHECKOUT_BASE"], ".ssh", "id_rsa")
    FileUtils.mkdir_p File.join(ENV["ENTITLEMENTS_ACCEPTANCE_GIT_CHECKOUT_BASE"], ".ssh")
    File.open(File.join(ENV["GIT_REPO_SSH_KEY"]), "w") do |f|
      f.write(Base64.decode64(File.read(File.expand_path("../git-server/private/id_rsa.base64", __dir__))))
    end

    # Git repo
    ENV["GIT_REPO_CHECKOUT_DIRECTORY"] = File.join(ENV["ENTITLEMENTS_ACCEPTANCE_GIT_CHECKOUT_BASE"], "git-repos")
  end

  config.after(:suite) do
    if File.directory?(ENV["ENTITLEMENTS_ACCEPTANCE_GIT_CHECKOUT_BASE"])
      FileUtils.remove_entry_secure(ENV["ENTITLEMENTS_ACCEPTANCE_GIT_CHECKOUT_BASE"])
    end
    ENV["ENTITLEMENTS_ACCEPTANCE_GIT_CHECKOUT_BASE"] = nil
    ENV["GIT_REPO_SSH_KEY"] = nil
    ENV["GIT_REPO_CHECKOUT_DIRECTORY"] = nil
  end
end

def fixture(path)
  File.expand_path(File.join("../fixtures", path.sub(%r{\A/+}, "")), File.dirname(__FILE__))
end

def run(fixture_dir, args = [])
  binary = File.expand_path("../../../bin/deploy-entitlements", File.dirname(__FILE__))
  configfile = fixture(File.join(fixture_dir, "config.yaml"))
  command_parts = [binary, "--config-file", configfile] + args
  command = command_parts.map { |i| Shellwords.escape(i) }.join(" ")
  stdout, stderr, exitstatus = Open3.capture3(command)
  OpenStruct.new({ stdout: stdout, stderr: stderr, exitstatus: exitstatus.exitstatus, success?: exitstatus.exitstatus == 0 })
end

def log(priority, pattern)
  Regexp.new("^#{priority[0].upcase}, \\[[^\\]]+\\]\s+#{priority.upcase} -- : #{pattern}")
end

def ldap_exist?(dn)
  ldap_obj.search(base: dn, scope: Net::LDAP::SearchScope_BaseObject, return_result: false)
end

def ldap_obj
  @ldap_obj ||= begin
    uri = URI(ENV["LDAP_URI"])

    ldap_object = Net::LDAP.new(
      host: uri.host,
      port: uri.port,
      encryption: (uri.scheme == "ldaps" ? :simple_tls : nil),
      auth: {method: :simple, username: ENV["LDAP_BINDDN"], password: ENV["LDAP_BINDPW"]}
    )

    ldap_object.bind
    operation_result = ldap_object.get_operation_result
    if operation_result["code"] != 0
      raise "spec_helper failed to bind to LDAP: #{operation_result['code']} - #{operation_result['message']}"
    end

    ldap_object
  end
end

def ldap_entry(dn)
  result = nil
  ldap_obj.search(base: dn, scope: Net::LDAP::SearchScope_BaseObject, return_result: true) do |entry|
    if result
      raise "Duplicate LDAP result for #{dn}. This=#{entry.inspect} ldap_entry=#{ldap_entry.inspect}"
    end
    result = entry
  end
  result
end

# Helper for acceptance testing
def github_http_get(uri)
  u = URI(File.join("https://github.fake", uri))
  Net::HTTP.start(u.host, u.port, use_ssl: true) do |http|
    request = Net::HTTP::Get.new(u.request_uri)
    request["Authorization"] = "token meowmeowmeowmeowmeow"
    http.request(request)
  end
end

def github_http_put(uri, query)
  u = URI(File.join("https://github.fake", uri))
  Net::HTTP.start(u.host, u.port, use_ssl: true) do |http|
    request = Net::HTTP::Put.new(u.request_uri)
    request["Authorization"] = "token meowmeowmeowmeowmeow"
    request.body = JSON.generate(query)
    http.request(request)
  end
end

def members(dn)
  result = ldap_entry(dn)
  raise "No LDAP group found for #{dn}!" unless result
  if result[:objectclass].include?("groupOfUniqueNames")
    Set.new(result[:uniquemember].map { |u| u.downcase })
  elsif result[:objectclass].include?("groupOfNames")
    Set.new(result[:member].map { |u| u.downcase })
  elsif result[:objectclass].include?("posixGroup")
    Set.new(result[:memberuid].map { |u| u.downcase })
  else
    Set.new
  end
end

def people_set(people_array)
  Set.new(people_array.map { |uid| "uid=#{uid.downcase},ou=people,dc=kittens,dc=net" })
end

# SSH key for the git server in the entitlements container
def setup_git_ssh_key
  return if File.file?(File.join(ENV["HOME"], ".ssh", "id_rsa"))
end

# Recursive tree using rugged - return an array of the files found.
# "result" should be started as an empty hash and will be populated with { "filename" => "content" }.
def rugged_recursive_tree(repo, tree, path, result)
  tree.each_blob do |entry|
    key = File.join(path, entry[:name])
    result[key] = repo.lookup(entry[:oid]).content
  end

  tree.each_tree do |entry|
    new_tree = repo.lookup(entry[:oid])
    rugged_recursive_tree(repo, new_tree, File.join(path, entry[:name]), result)
  end
end
