# frozen_string_literal: true

require_relative "lib/version"

Gem::Specification.new do |s|
  s.name = ENV["GEM_NAME"] || "entitlements-app"
  s.version = Entitlements::Version::VERSION
  s.summary = "git-managed LDAP group configurations"
  s.description = "The Ruby Gem that Powers Entitlements - GitHub's Identity and Access Management System"
  s.authors = ["GitHub, Inc. Security Ops"]
  s.email = "opensource+entitlements-app@github.com"
  s.license = "MIT"
  s.files = Dir.glob("lib/**/*") + %w[bin/deploy-entitlements]
  s.homepage = "https://github.com/github/entitlements-app"
  s.executables = %w[deploy-entitlements]

  s.required_ruby_version = ">= 3.0.0"

  s.add_dependency "concurrent-ruby", "~> 1.3", ">= 1.3.1"
  s.add_dependency "faraday", "~> 2.0"
  s.add_dependency "net-ldap", "~> 0.19"
  s.add_dependency "octokit", "~> 4.18"
  s.add_dependency "optimist", "~> 3.1"

  s.add_development_dependency "debug", "<= 1.8.0"
  s.add_development_dependency "rake", "~> 13.2", ">= 13.2.1"
  s.add_development_dependency "rspec", "= 3.8.0"
  s.add_development_dependency "rubocop", "~> 1.64"
  s.add_development_dependency "rubocop-github", "~> 0.20"
  s.add_development_dependency "rubocop-performance", "~> 1.21"
  s.add_development_dependency "rugged", "~> 1.7", ">= 1.7.2"
  s.add_development_dependency "simplecov", "= 0.16.1"
  s.add_development_dependency "simplecov-erb", "= 1.0.1"
  s.add_development_dependency "vcr", "= 4.0.0"
  s.add_development_dependency "webmock", "3.4.2"
end
