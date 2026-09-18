# frozen_string_literal: true

require "fileutils"
require "extralite"

module Entitlements
  class SmartDiff
    class Database
      SCHEMA = <<~SQL
        PRAGMA foreign_keys = ON;

        CREATE TABLE metadata (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          schema_version INTEGER NOT NULL,
          evaluated_at TEXT NOT NULL,
          scoped INTEGER NOT NULL CHECK (scoped IN (0, 1))
        );

        CREATE TABLE snapshots (
          snapshot TEXT PRIMARY KEY CHECK (snapshot IN ('base', 'head')),
          source_sha TEXT NOT NULL,
          people_snapshot_sha256 TEXT NOT NULL
        );

        CREATE TABLE affected_groups (
          entitlement_group TEXT PRIMARY KEY
        );

        CREATE TABLE membership_changes (
          change_type TEXT NOT NULL CHECK (change_type IN ('gain', 'loss')),
          backend TEXT NOT NULL,
          entitlement_group TEXT NOT NULL,
          username TEXT NOT NULL,
          PRIMARY KEY (change_type, backend, entitlement_group, username)
        );

        CREATE TABLE people (
          snapshot TEXT NOT NULL CHECK (snapshot IN ('base', 'head')),
          username TEXT NOT NULL,
          PRIMARY KEY (snapshot, username),
          FOREIGN KEY (snapshot) REFERENCES snapshots(snapshot)
        );

        CREATE TABLE person_facts (
          snapshot TEXT NOT NULL CHECK (snapshot IN ('base', 'head')),
          username TEXT NOT NULL,
          attribute TEXT NOT NULL,
          value TEXT NOT NULL,
          PRIMARY KEY (snapshot, username, attribute, value),
          FOREIGN KEY (snapshot, username) REFERENCES people(snapshot, username)
        );
      SQL

      def self.write(path:, result:)
        FileUtils.rm_f(path)
        db = Extralite::Database.new(path)
        db.execute(SCHEMA)
        db.transaction do
          insert_result(db, result)
        end
        db.execute("PRAGMA optimize")
      ensure
        db&.close
      end

      def self.read(path)
        db = Extralite::Database.new(path)
        yield db
      ensure
        db&.close
      end

      def self.markdown(path:, limit:)
        result = read(path) { |db| result_from(db) }
        Entitlements::SmartDiff.markdown(result, limit: limit)
      end

      def self.insert_result(db, result)
        db.execute(
          "INSERT INTO metadata (id, schema_version, evaluated_at, scoped) VALUES (1, ?, ?, ?)",
          result.fetch("schema_version"),
          result.fetch("base").fetch("evaluated_at"),
          result.key?("scope") ? 1 : 0
        )
        %w[base head].each do |snapshot|
          metadata = result.fetch(snapshot)
          db.execute(
            "INSERT INTO snapshots (snapshot, source_sha, people_snapshot_sha256) VALUES (?, ?, ?)",
            snapshot,
            metadata.fetch("source_sha"),
            metadata.fetch("people_snapshot_sha256")
          )
        end
        result.fetch("scope", {}).fetch("affected_groups", []).each do |group|
          db.execute("INSERT INTO affected_groups (entitlement_group) VALUES (?)", group)
        end
        {"gain" => "gains", "loss" => "losses"}.each do |change_type, key|
          result.fetch(key).each do |record|
            db.execute(
              "INSERT INTO membership_changes (change_type, backend, entitlement_group, username) VALUES (?, ?, ?, ?)",
              change_type,
              record.fetch("backend"),
              record.fetch("entitlement_group"),
              record.fetch("username")
            )
          end
        end
        result.fetch("people").each do |snapshot, people|
          people.each do |record|
            db.execute(
              "INSERT INTO people (snapshot, username) VALUES (?, ?)",
              snapshot,
              record.fetch("username")
            )
            record.fetch("attributes").each do |attribute, value|
              fact_values(value, username: record.fetch("username"), attribute: attribute).each do |fact_value|
                db.execute(
                  "INSERT INTO person_facts (snapshot, username, attribute, value) VALUES (?, ?, ?, ?)",
                  snapshot,
                  record.fetch("username"),
                  attribute,
                  fact_value
                )
              end
            end
          end
        end
      end
      private_class_method :insert_result

      def self.fact_values(value, username:, attribute:)
        values = value.is_a?(Array) ? value : [value]
        if values.any? { |item| item.is_a?(Array) || item.is_a?(Hash) }
          raise ArgumentError, "Identity attribute #{attribute.inspect} for #{username} must contain scalar values"
        end

        values.compact.map(&:to_s).uniq
      end
      private_class_method :fact_values

      def self.result_from(db)
        metadata = db.query_single("SELECT schema_version, evaluated_at, scoped FROM metadata WHERE id = 1")
        snapshots = db.query("SELECT snapshot, source_sha, people_snapshot_sha256 FROM snapshots").to_h do |row|
          [
            row.fetch(:snapshot),
            {
              "source_sha" => row.fetch(:source_sha),
              "people_snapshot_sha256" => row.fetch(:people_snapshot_sha256),
              "evaluated_at" => metadata.fetch(:evaluated_at)
            }
          ]
        end
        result = {
          "schema_version" => metadata.fetch(:schema_version),
          "base" => snapshots.fetch("base"),
          "head" => snapshots.fetch("head"),
          "counts" => {
            "gains" => db.query_single_splat("SELECT count(*) FROM membership_changes WHERE change_type = 'gain'"),
            "losses" => db.query_single_splat("SELECT count(*) FROM membership_changes WHERE change_type = 'loss'")
          },
          "gains" => membership_changes(db, "gain"),
          "losses" => membership_changes(db, "loss")
        }
        groups = db.query("SELECT entitlement_group FROM affected_groups ORDER BY entitlement_group").map do |row|
          row.fetch(:entitlement_group)
        end
        result["scope"] = {"affected_groups" => groups} if metadata.fetch(:scoped) == 1
        result
      end
      private_class_method :result_from

      def self.membership_changes(db, change_type)
        rows = db.query(<<~SQL, change_type)
          SELECT backend, entitlement_group, username
          FROM membership_changes
          WHERE change_type = ?
          ORDER BY backend, entitlement_group, username
        SQL
        rows.map do |row|
          {
            "backend" => row.fetch(:backend),
            "entitlement_group" => row.fetch(:entitlement_group),
            "username" => row.fetch(:username)
          }
        end
      end
      private_class_method :membership_changes
    end
  end
end
