# frozen_string_literal: true

require "base64"

# Note that contracts.ruby has two specific ruby-version specific libraries, which we have vendored into lib/
if (Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0")) # ruby3
  $LOAD_PATH.unshift(File.expand_path("../../lib/contracts-ruby3/lib"))
else # ruby2
  $LOAD_PATH.unshift(File.expand_path("../../lib/contracts-ruby2/lib"))
end

require "contracts"
require "json"
require "rspec"
require "rspec/support"
require "rspec/support/object_formatter"
require "simplecov"
require "simplecov-erb"
require "tempfile"
require "vcr"
require "webmock/rspec"

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::ERBFormatter
]
SimpleCov.start do
  # don't show specs as missing coverage for themselves
  add_filter "/spec/"

  # don't analyze coverage for gems
  add_filter "/vendor/gems/"
end

require_relative "../../lib/entitlements"

def fixture(path)
  File.expand_path(File.join("fixtures", path.sub(%r{\A/+}, "")), File.dirname(__FILE__))
end

def default_filters
  {
    "contractors" => :none,
    "lockout"     => :none,
    "pre-hires"   => :none,
  }
end

def graphql_response(team, slice_start, slice_length)
  team_id = rand(1..10000)
  edges = team.members.sort.to_a.slice(slice_start, slice_length).map do |m|
    { "node" => { "login" => m }, "cursor" => Base64.encode64(m) }
  end
  struct = {
    "data" => {
      "organization" => {
        "team" => {
          "databaseId" => team_id,
          "members" => {
            "edges" => edges
          }
        }
      }
    }
  }
  JSON.generate(struct)
end

RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = 100000

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.default_cassette_options = { record: :once }
  config.hook_into :webmock
end
# These classes need to be stubbed since they come in via `load_extra` and need to be defined at
# compile time for some tests. But we are not necessarily loading every extra for every test.
module Entitlements
  module Extras
    class Base; end
    class LDAPGroup
      class Base < Entitlements::Extras::Base; end
      class Filters
        class MemberOfLDAPGroup < Entitlements::Data::Groups::Calculated::Filters::Base; end
      end
      class Rules
        class LDAPGroup < Entitlements::Data::Groups::Calculated::Rules::Base; end
      end
    end
    class Orgchart
      class Base < Entitlements::Extras::Base; end
      class Logic; end
      class PersonMethods < Entitlements::Extras::Orgchart::Base; end
      class Rules
        class DirectReport < Entitlements::Data::Groups::Calculated::Rules::Base; end
        class Management < Entitlements::Data::Groups::Calculated::Rules::Base; end
      end
    end
  end
end

def setup_default_filters
  contractor_cfg = {
    class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup,
    config: { "group" => "internal/contractors" }
  }
  lockout_cfg = {
    class: Entitlements::Extras::LDAPGroup::Filters::MemberOfLDAPGroup,
    config: { "ldap_group" => "cn=lockout,ou=Groups,dc=kittens,dc=net" }
  }
  pre_hire_cfg = {
    class: Entitlements::Data::Groups::Calculated::Filters::MemberOfGroup,
    config: { "group" => "internal/pre-hires" }
  }
  Entitlements::Data::Groups::Calculated.register_filter("contractors", contractor_cfg)
  Entitlements::Data::Groups::Calculated.register_filter("lockout", lockout_cfg)
  Entitlements::Data::Groups::Calculated.register_filter("pre-hires", pre_hire_cfg)
end

module MyLetDeclarations
  extend RSpec::SharedContext
  let(:cache) { {} }
  let(:entitlements_config_file) { fixture("config.yaml") }
  let(:entitlements_config_hash) { nil }
  let(:logger) { Entitlements.dummy_logger }
end

module Contracts
  module RSpec
    module Mocks
      def instance_double(klass, *args)
        super.tap do |double|
          allow(double).to receive(:is_a?).with(klass).and_return(true)
          allow(double).to receive(:is_a?).with(ParamContractError).and_return(false)
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include MyLetDeclarations
  config.include Contracts::RSpec::Mocks

  config.before :each do
    allow(Time).to receive(:now).and_return(Time.utc(2018, 4, 1, 12, 0, 0))
    allow(Entitlements).to receive(:cache).and_return(cache)
    if entitlements_config_hash
      Entitlements.config = entitlements_config_hash
    else
      Entitlements.config_file = entitlements_config_file
      Entitlements.validate_configuration_file!
    end
    Entitlements.set_logger(logger)
  end

  config.after :each do
    Entitlements.reset!
  end
end
