# frozen_string_literal: true

require_relative "groups/cached"
require_relative "groups/calculated"

module Entitlements
  class Data
    class Groups
      class DuplicateGroupError < RuntimeError; end
      class GroupNotFoundError < RuntimeError; end
    end
  end
end
