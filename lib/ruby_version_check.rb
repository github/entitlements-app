https://github.com/github/entitlements-app.git# frozen_string_literal: true

module RubyVersionCheck
  # Allows maintaining version compatibility with older versions of Ruby
  # :nocov:
  def self.ruby_version2?
    @ruby_version2 ||= (
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.0.0") &&
        Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.0.0")
    )
  end

  def self.ruby_version3?
    @ruby_version3 ||= (Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0"))
  end
  # :nocov:
end
