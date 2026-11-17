# Migration cases (Room): the rules

Moved word for word from `SKILL.md`: the section "Migration cases (Room)". The rules are unchanged; they are still cited as `tm-testing`, "Migration cases (Room)".

## Migration cases (Room)

When you write a Room migration case or a frozen fixture, read `room-migration-tests.md` first: the
harness files and how a fixture is built from the schema file.

This section is the canonical statement of the migration test (step 5 of the schema procedure). The
schema change procedure around it is in `tm-kmp-shared`, "Changing the database schema (Room)". Each
case writes a database file at an old version with plain SQL, outside Room, opens it through the
app's builder pipeline and `appMigrations`, and reads every row back through the DAO.

For a migration from M to N:
- If version M has no fixture yet, add one: its `schemaStatements` are copied from
  `data/schemas/.../M.json`, its rows are `INSERT` statements in version M's stored form written as
  literal text (never produced by the current converters), and it goes into
  `frozenDatabaseVersions`. `FrozenDatabaseVersionsSchemaTest` (host only) fails when a fixture
  differs from its schema file. Rows cover every column: each `ActivityType` name, null and non-null
  optional columns, empty and non-empty coordinate lists. A fixture never changes once its version
  has shipped.
- Add one case whose name contains `MIGRATION_M_N` (the schema check's rule (c) looks for that
  text). It opens the fixture and asserts, with `assertEquals` on whole `ActivityEntity` lists,
  every field of every row at N, including the value the migration gives each new or changed
  column, and the stored `user_version` N.
- A test that only names `MIGRATION_M_N`, or asserts a row count without the rows' fields, does
  not satisfy the reviewer: the schema check accepts it, so the assertions are what prove the
  rows survive.

Check a new case once in the working tree: break the migration (for example add a `DELETE` of one
row) and see the case fail on both platforms on the row assertion, then restore.
