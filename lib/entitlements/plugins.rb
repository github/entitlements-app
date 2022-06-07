# frozen_string_literal: true

module Entitlements
  class Plugins
    def self.loaded?
      true
    end

    def self.override_hash(*args)
      raise "Please define override_hash in the child class #{self}!"
    end
  end
end
