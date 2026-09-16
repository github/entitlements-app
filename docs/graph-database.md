# Graph database output

Entitlements can export the graph it computes during a run &mdash; the groups, the people, the
membership edges between them, the group-to-group references, and the changes applied &mdash; into a
single self-contained [SQLite](https://www.sqlite.org/) database file. The file can then be queried
ad hoc with the `sqlite3` shell, with Datasette, with any programming language, or loaded into a
data warehouse.

## Why SQLite

The entitlements graph is relational and recursive (groups may reference other groups), it is
sparse (metadata and person attributes are heterogeneous bags), and the data volume is modest. Those
characteristics favor a row-oriented engine with real SQL over a columnar file format:

| Format | Notes |
| ------ | ----- |
| **SQLite** | Single file, no server, supported everywhere. `WITH RECURSIVE` answers group-of-group expansion directly. Ruby support requires only the `sqlite3` gem, which ships precompiled for mainstream platforms. **This is what Entitlements writes.** |
| Parquet | Columnar and great for warehouse scans, but it is a file format, not a query engine: no joins, no indexes, no recursive queries on its own. Writing it from Ruby requires the Apache Arrow C++ libraries. |
| DuckDB | Excellent query engine, but the Ruby binding requires a separately installed `libduckdb`, and the storage format has not historically been stable across versions &mdash; a problem for archived snapshots. |
| JSON / CSV | Trivial to produce but push all query work onto consumers. |
| Graph stores | Conceptually close, but add heavy non-Ruby dependencies for queries that recursive CTEs already handle. |

Choosing SQLite does not close the door on the others: a snapshot can be converted with, for
example, `duckdb -c "INSTALL sqlite; ATTACH 'entitlements.db' (TYPE sqlite); COPY (SELECT * FROM membership) TO 'membership.parquet'"`.

## Configuration

The exporter is an auditor, so it runs after the calculated changes have been applied. Add it to
the `auditors` section of your Entitlements configuration file:

```yaml
auditors:
  - auditor_class: SQLite
    path: /var/lib/entitlements/entitlements.db
    person_attributes:
      - githubdotcomid
```

| Key | Required | Description |
| --- | -------- | ----------- |
| `path` | yes | Where to write the database file. Parent directories are created as needed. |
| `person_attributes` | no | Allowlist of person attributes to record. When omitted, only user IDs are stored, so that no additional personal data ends up in the artifact. |
| `description` | no | Human readable description, as with any auditor. |
| `provider_id` | no | Identifier used in log messages, as with any auditor. |

The `sqlite3` gem is an optional dependency of `entitlements-app`. Install it (`gem install sqlite3`
or add it to your `Gemfile`) if you enable this auditor; the auditor fails during setup with a clear
message when the gem is missing. Auditors do not run in no-op mode, so a database is written only on
runs that apply changes.

Each run writes a complete snapshot. The database is built at a temporary path and then renamed into
place, so readers never observe a partially written file. Rows are inserted in sorted order with a
fixed page size and the database is vacuumed at the end, so two runs over identical input produce
byte-identical files apart from the `generated_at` timestamp recorded in the `run` table.

## Schema

`PRAGMA user_version` holds the schema version, which is also recorded in `run.schema_version`.

| Table | Contents |
| ----- | -------- |
| `run` | One row of run metadata: `generated_at`, `entitlements_version`, `schema_version`, `configuration_path`, `provider_exception`. |
| `ou` | One row per configured OU: `ou_key`, `base_dn`, `type`. |
| `group` | Group nodes: `dn`, `cn`, `ou_key`, `description`, `filename`. |
| `group_metadata` | Long-form group metadata: `dn`, `key`, `value`. Non-scalar values are JSON encoded, so the SQLite JSON functions work on them. |
| `person` | Person nodes: `uid`. |
| `person_attribute` | Long-form person attributes: `uid`, `name`, `value`. Populated only for allowlisted attributes. |
| `membership` | Direct membership edges: `group_dn`, `uid`. |
| `group_dependency` | Group-to-group reference edges: `parent_reference`, `child_reference`, and the resolved `parent_dn` / `child_dn` when the referenced group was part of this run. |
| `action` | Changes calculated in this run: `dn`, `ou_key`, `change_type` (`add`, `update`, `delete`), `applied`. |
| `action_member` | Per-user membership changes: `dn`, `uid`, `change_type` (`add` or `remove`). |

Views:

| View | Contents |
| ---- | -------- |
| `group_dependency_closure` | Transitive closure of `group_dependency` with the shortest `depth`. Depth is capped so that a circular reference terminates. |
| `expanded_membership` | Membership of each group including everyone picked up through group references, with `depth` and `via_group_dn`. |
| `person_entitlement` | One row per entitlement held by a person, joined to group details. |
| `empty_group` | Groups that were calculated with no members. |

## Example queries

Every entitlement held by a person:

```sql
SELECT group_dn, filename FROM person_entitlement WHERE uid = 'blackmanx' ORDER BY group_dn;
```

The largest entitlements:

```sql
SELECT group_dn, COUNT(*) AS members
  FROM membership
 GROUP BY group_dn
 ORDER BY members DESC
 LIMIT 25;
```

Which groups a given entitlement is pulled into, directly or indirectly:

```sql
SELECT ancestor_dn, depth
  FROM group_dependency_closure
 WHERE descendant_dn = 'cn=team-a,ou=Groups,dc=example,dc=net'
 ORDER BY depth, ancestor_dn;
```

Everything that changed in this run:

```sql
SELECT action.dn, action.change_type, action_member.uid, action_member.change_type
  FROM action
  LEFT JOIN action_member ON action_member.dn = action.dn
 WHERE action.applied = 1
 ORDER BY action.dn, action_member.uid;
```

Groups whose membership only comes from other groups:

```sql
SELECT DISTINCT ancestor_dn
  FROM group_dependency_closure
 WHERE ancestor_dn IN (SELECT dn FROM empty_group);
```

Query a metadata key:

```sql
SELECT dn, value FROM group_metadata WHERE key = 'team_name' ORDER BY dn;
```
