# frozen_string_literal: true

require "json"
require_relative "../../entitlements"

module Entitlements
  class SmartDiff
    class SnapshotWorker
      def self.run(input: $stdin, output: $stdout, error: $stderr)
        request = JSON.parse(input.read)
        people_source = request["people_source"]
        snapshot = if people_source
                     export(request, people_source)
                   else
                     Entitlements::SmartDiff::IdentitySnapshot.with_file(request.fetch("tree_root")) do |path|
                       export(request, path)
                     end
                   end
        output.write(JSON.generate(snapshot))
        0
      rescue StandardError => e
        error.puts "#{e.class}: #{e.message}"
        1
      end

      def self.export(request, people_source)
        Entitlements::DesiredGroups.export(
          config_file: request.fetch("config_file"),
          source_sha: request.fetch("source_sha"),
          people_source: people_source,
          evaluated_at: request.fetch("evaluated_at"),
          tree_root: request["tree_root"],
          entitlement_groups: request["entitlement_groups"]
        )
      end
      private_class_method :export
    end
  end
end

# :nocov:
exit Entitlements::SmartDiff::SnapshotWorker.run if $PROGRAM_NAME == __FILE__
# :nocov:
