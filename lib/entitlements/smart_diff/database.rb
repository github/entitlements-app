# frozen_string_literal: true

require "json"
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
          attributes_json TEXT NOT NULL CHECK (json_valid(attributes_json)),
          PRIMARY KEY (snapshot, username),
          FOREIGN KEY (snapshot) REFERENCES snapshots(snapshot)
        );

        CREATE VIEW change_context AS
        SELECT
          changes.change_type,
          changes.backend,
          changes.entitlement_group,
          changes.username,
          base_people.attributes_json AS base_attributes_json,
          head_people.attributes_json AS head_attributes_json
        FROM membership_changes AS changes
        LEFT JOIN people AS base_people
          ON base_people.snapshot = 'base' AND base_people.username = changes.username
        LEFT JOIN people AS head_people
          ON head_people.snapshot = 'head' AND head_people.username = changes.username;

        CREATE TABLE policy_rules (
          rule_id TEXT PRIMARY KEY,
          decision TEXT NOT NULL CHECK (decision IN ('auto_approve', 'human_review')),
          description TEXT NOT NULL
        );

        CREATE TABLE policy_matches (
          change_type TEXT NOT NULL,
          backend TEXT NOT NULL,
          entitlement_group TEXT NOT NULL,
          username TEXT NOT NULL,
          rule_id TEXT NOT NULL,
          PRIMARY KEY (change_type, backend, entitlement_group, username, rule_id),
          FOREIGN KEY (change_type, backend, entitlement_group, username)
            REFERENCES membership_changes(change_type, backend, entitlement_group, username),
          FOREIGN KEY (rule_id) REFERENCES policy_rules(rule_id)
        );

        CREATE TABLE policy_evaluations (
          change_type TEXT NOT NULL,
          backend TEXT NOT NULL,
          entitlement_group TEXT NOT NULL,
          username TEXT NOT NULL,
          decision TEXT NOT NULL CHECK (decision IN ('auto_approve', 'human_review')),
          reason TEXT NOT NULL,
          PRIMARY KEY (change_type, backend, entitlement_group, username),
          FOREIGN KEY (change_type, backend, entitlement_group, username)
            REFERENCES membership_changes(change_type, backend, entitlement_group, username)
        );

        CREATE TABLE policy_result (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          policy_version INTEGER NOT NULL,
          decision TEXT NOT NULL CHECK (decision IN ('auto_approve', 'human_review')),
          evaluated_count INTEGER NOT NULL,
          auto_approve_count INTEGER NOT NULL,
          human_review_count INTEGER NOT NULL
        );

        CREATE TABLE policy_reasons (
          position INTEGER PRIMARY KEY,
          reason TEXT NOT NULL
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
              "INSERT INTO people (snapshot, username, attributes_json) VALUES (?, ?, ?)",
              snapshot,
              record.fetch("username"),
              JSON.generate(record.fetch("attributes"))
            )
          end
        end
      end
      private_class_method :insert_result

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
