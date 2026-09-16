# frozen_string_literal: true

require "json"
require_relative "../../entitlements"

module Entitlements
  class SmartDiff
    class SnapshotWorker
      def self.run(input: $stdin, output: $stdout, error: $stderr)
        request = JSON.parse(input.read)
        snapshot = Entitlements::DesiredGroups.export(
          config_file: request.fetch("config_file"),
          source_sha: request.fetch("source_sha"),
          people_source: request.fetch("people_source"),
          evaluated_at: request.fetch("evaluated_at"),
          tree_root: request["tree_root"],
          entitlement_groups: request["entitlement_groups"]
        )
        output.write(JSON.generate(snapshot))
        0
      rescue StandardError => e
        error.puts "#{e.class}: #{e.message}"
        1
      end
    end
  end
end

# :nocov:
exit Entitlements::SmartDiff::SnapshotWorker.run if $PROGRAM_NAME == __FILE__
# :nocov:
