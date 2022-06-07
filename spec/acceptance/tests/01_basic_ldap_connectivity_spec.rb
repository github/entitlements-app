# frozen_string_literal: true

# By the time we run this test we have already tested connectivity from the master script. However running
# this basic verification could detect basic connection, authentication, or authorization failures right
# away, before moving into more complicated tests.

require_relative "spec_helper"

describe Entitlements do
  let(:dn) { "uid=emmy,ou=Service_Accounts,dc=kittens,dc=net" }

  before(:all) do
    @stringio = StringIO.new
    logger = Logger.new(@stringio)
    Entitlements.set_logger(logger)
    ldap = Entitlements::Service::LDAP.new(
      addr: ENV["LDAP_URI"],
      binddn: ENV["LDAP_BINDDN"],
      bindpw: ENV["LDAP_BINDPW"],
      person_dn_format: "uid=%KEY%,ou=People,dc=kittens,dc=net"
    )
    @result = ldap.search(base: ENV["LDAP_BINDDN"], attrs: "*")
  end

  it "returns the expected result from a search" do
    expect(@result).to be_a_kind_of(Hash)
    expect(@result[dn]).to be_a_kind_of(Net::LDAP::Entry)
    expect(@result[dn].dn).to eq(dn)
    expect(@result[dn][:uid].first).to eq("emmy")
    expect(@result[dn][:userpassword].first).to eq("kittens")
  end

  it "logs the expected messages" do
    expect(@stringio.string).to match(/LDAP Search: filter=nil base=\"uid=emmy,ou=Service_Accounts,dc=kittens,dc=net/)
    expect(@stringio.string).to match(/Creating connection to ldap-server.fake port 636/)
    expect(@stringio.string).to match(/Binding with user \"uid=emmy,ou=Service_Accounts,dc=kittens,dc=net\" with simple/)
    expect(@stringio.string).to match(/Successfully authenticated to ldap-server.fake port 636/)
    expect(@stringio.string).to match(/Completed search: 1 result/)
  end
end
