# frozen_string_literal: true

# Writes an Entitlements::Graph::Snapshot to a self-contained SQLite database file.
#
# SQLite was chosen over columnar formats (Parquet) and other embedded engines because the
# entitlements graph is relational and recursive (group-of-group expansion), the data volume
# is modest, and a `.db` file is queryable everywhere without a server or a build toolchain.
# A snapshot can still be converted to Parquet later (for example with DuckDB's sqlite
# scanner) if a data warehouse consumer appears.
#
# The `sqlite3` gem is an optional dependency: it is required lazily so that installations
# which do not use this feature do not need it.
#
# Output is deterministic: rows are inserted in the sorted order produced by the snapshot, the
# page size is fixed, and the database is vacuumed before it is moved into place. Two runs over
# identical input therefore produce byte-identical files, apart from the `generated_at`
# timestamp that the snapshot records in the `run` table.

require "fileutils"
require "securerandom"

module Entitlements
  class Graph
    class SQLiteWriter
      include ::Contracts::Core
      C = ::Contracts

      class DriverUnavailable < RuntimeError; end

      # Identifies files produced by this writer: `sqlite3 file.db` / `PRAGMA application_id`.
      APPLICATION_ID = 0x454E546C

      # Fixed page size so that identical input produces an identical file.
      PAGE_SIZE = 4096

      # Guard rail for the recursive views, so that a circular group reference cannot
      # produce an unbounded result set.
      MAX_DEPENDENCY_DEPTH = 64

      SCHEMA = [
        <<~SQL,
          CREATE TABLE run (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            generated_at TEXT NOT NULL,
            entitlements_version TEXT NOT NULL,
            schema_version INTEGER NOT NULL,
            configuration_path TEXT,
            provider_exception TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE ou (
            ou_key TEXT PRIMARY KEY,
            base_dn TEXT,
            type TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE "group" (
            dn TEXT PRIMARY KEY,
            cn TEXT NOT NULL,
            ou_key TEXT NOT NULL REFERENCES ou(ou_key),
            description TEXT,
            filename TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE group_metadata (
            dn TEXT NOT NULL REFERENCES "group"(dn),
            key TEXT NOT NULL,
            value TEXT,
            PRIMARY KEY (dn, key)
          )
        SQL
        <<~SQL,
          CREATE TABLE person (
            uid TEXT PRIMARY KEY
          )
        SQL
        <<~SQL,
          CREATE TABLE person_attribute (
            uid TEXT NOT NULL REFERENCES person(uid),
            name TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (uid, name, value)
          )
        SQL
        <<~SQL,
          CREATE TABLE membership (
            group_dn TEXT NOT NULL REFERENCES "group"(dn),
            uid TEXT NOT NULL REFERENCES person(uid),
            PRIMARY KEY (group_dn, uid)
          )
        SQL
        <<~SQL,
          CREATE TABLE group_dependency (
            parent_reference TEXT NOT NULL,
            child_reference TEXT NOT NULL,
            parent_dn TEXT,
            child_dn TEXT,
            PRIMARY KEY (parent_reference, child_reference)
          )
        SQL
        <<~SQL,
          CREATE TABLE action (
            dn TEXT NOT NULL,
            ou_key TEXT NOT NULL,
            change_type TEXT NOT NULL,
            applied INTEGER NOT NULL,
            PRIMARY KEY (dn)
          )
        SQL
        <<~SQL,
          CREATE TABLE action_member (
            dn TEXT NOT NULL REFERENCES action(dn),
            uid TEXT NOT NULL,
            change_type TEXT NOT NULL,
            PRIMARY KEY (dn, uid, change_type)
          )
        SQL
        "CREATE INDEX index_membership_uid ON membership(uid)",
        "CREATE INDEX index_group_ou_key ON \"group\"(ou_key)",
        "CREATE INDEX index_group_dependency_child_dn ON group_dependency(child_dn)",
        "CREATE INDEX index_action_member_uid ON action_member(uid)"
      ].freeze

      VIEWS = [
        # Transitive closure of the group-of-group references, capped in depth so that a
        # circular reference terminates.
        <<~SQL,
          CREATE VIEW group_dependency_closure AS
          WITH RECURSIVE closure(ancestor_dn, descendant_dn, depth) AS (
            SELECT parent_dn, child_dn, 1
              FROM group_dependency
             WHERE parent_dn IS NOT NULL AND child_dn IS NOT NULL
            UNION
            SELECT closure.ancestor_dn, group_dependency.child_dn, closure.depth + 1
              FROM closure
              JOIN group_dependency ON group_dependency.parent_dn = closure.descendant_dn
             WHERE group_dependency.child_dn IS NOT NULL
               AND closure.depth < #{MAX_DEPENDENCY_DEPTH}
          )
          SELECT ancestor_dn, descendant_dn, MIN(depth) AS depth
            FROM closure
           GROUP BY ancestor_dn, descendant_dn
        SQL
        # Membership of a group including everyone it picks up through group references.
        <<~SQL,
          CREATE VIEW expanded_membership AS
          SELECT group_dn AS group_dn, uid AS uid, 0 AS depth, group_dn AS via_group_dn
            FROM membership
          UNION
          SELECT closure.ancestor_dn, membership.uid, closure.depth, membership.group_dn
            FROM group_dependency_closure AS closure
            JOIN membership ON membership.group_dn = closure.descendant_dn
        SQL
        # One row per entitlement held by a person.
        <<~SQL,
          CREATE VIEW person_entitlement AS
          SELECT membership.uid AS uid,
                 "group".dn AS group_dn,
                 "group".cn AS cn,
                 "group".ou_key AS ou_key,
                 "group".filename AS filename
            FROM membership
            JOIN "group" ON "group".dn = membership.group_dn
        SQL
        # Groups that were calculated with no members at all.
        <<~SQL
          CREATE VIEW empty_group AS
          SELECT "group".dn AS dn, "group".ou_key AS ou_key
            FROM "group"
           WHERE NOT EXISTS (SELECT 1 FROM membership WHERE membership.group_dn = "group".dn)
        SQL
      ].freeze

      # Determine whether the sqlite3 driver is available in this installation.
      #
      # Takes no arguments.
      #
      # Returns true if the driver could be loaded, false otherwise.
      Contract C::None => C::Bool
      def self.driver_available?
        load_driver!
        true
      rescue DriverUnavailable
        false
      end

      # Load the optional sqlite3 dependency.
      #
      # Takes no arguments.
      #
      # Returns nothing. Raises DriverUnavailable if the gem is not installed.
      Contract C::None => C::Any
      def self.load_driver!
        require "sqlite3"
      rescue LoadError => e
        raise DriverUnavailable, "The sqlite3 gem is required to write an Entitlements graph database: #{e.message}"
      end

      # Constructor.
      #
      # snapshot - An Entitlements::Graph::Snapshot object.
      Contract Entitlements::Graph::Snapshot => C::Any
      def initialize(snapshot)
        @snapshot = snapshot
      end

      # Write the snapshot to the given path. The database is built at a temporary path in
      # the same directory and then atomically renamed into place, so a reader never sees a
      # partially written database.
      #
      # path - A String with the destination file name.
      #
      # Returns the String path that was written.
      Contract String => String
      def write!(path)
        self.class.load_driver!

        FileUtils.mkdir_p(File.dirname(path))
        temporary_path = "#{path}.tmp.#{Process.pid}.#{SecureRandom.hex(8)}"

        begin
          db = SQLite3::Database.new(temporary_path)
          begin
            db.execute("PRAGMA page_size = #{PAGE_SIZE}")
            db.execute("PRAGMA journal_mode = OFF")
            db.execute("PRAGMA application_id = #{APPLICATION_ID}")
            db.execute("PRAGMA user_version = #{Entitlements::Graph::Snapshot::SCHEMA_VERSION}")

            SCHEMA.each { |statement| db.execute(statement) }
            VIEWS.each { |statement| db.execute(statement) }

            db.transaction { populate(db) }

            db.execute("VACUUM")
          ensure
            db.close
          end

          FileUtils.mv(temporary_path, path)
        ensure
          FileUtils.rm_f(temporary_path)
        end

        path
      end

      private

      attr_reader :snapshot

      # Insert all of the snapshot data. Rows are inserted in the order the snapshot
      # produced them, which is deterministic.
      #
      # db - A SQLite3::Database object.
      #
      # Returns nothing.
      Contract C::Any => C::Any
      def populate(db)
        db.execute(
          "INSERT INTO run (id, generated_at, entitlements_version, schema_version, configuration_path, provider_exception) VALUES (1, ?, ?, ?, ?, ?)",
          [
            snapshot.run.fetch("generated_at"),
            snapshot.run.fetch("entitlements_version"),
            snapshot.run.fetch("schema_version"),
            snapshot.run.fetch("configuration_path"),
            snapshot.run.fetch("provider_exception")
          ]
        )

        insert(db, "ou", %w[ou_key base_dn type], snapshot.ous)
        insert(db, "\"group\"", %w[dn cn ou_key description filename], snapshot.groups)
        insert(db, "group_metadata", %w[dn key value], snapshot.group_metadata)
        insert(db, "person", %w[uid], snapshot.people)
        insert(db, "person_attribute", %w[uid name value], snapshot.person_attributes)
        insert(db, "membership", %w[group_dn uid], snapshot.memberships)
        insert(db, "group_dependency", %w[parent_reference child_reference parent_dn child_dn], snapshot.dependencies)
        insert(db, "action", %w[dn ou_key change_type applied], snapshot.actions)
        insert(db, "action_member", %w[dn uid change_type], snapshot.action_members)
      end

      # Insert rows into a table using a prepared statement.
      #
      # db      - A SQLite3::Database object.
      # table   - A String with the (already quoted, if necessary) table name.
      # columns - An Array of Strings with the column names.
      # rows    - An Array of Hashes keyed by column name.
      #
      # Returns nothing.
      Contract C::Any, String, C::ArrayOf[String], C::ArrayOf[C::HashOf[String => C::Any]] => C::Any
      def insert(db, table, columns, rows)
        return if rows.empty?

        placeholders = Array.new(columns.size, "?").join(", ")
        statement = db.prepare("INSERT INTO #{table} (#{columns.join(', ')}) VALUES (#{placeholders})")
        begin
          rows.each { |row| statement.execute(columns.map { |column| row[column] }) }
        ensure
          statement.close
        end
      end
    end
  end
end
