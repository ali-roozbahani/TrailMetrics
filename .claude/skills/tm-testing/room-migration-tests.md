# Room migration tests: harness and fixture construction

Read from `SKILL.md`, "Migration cases (Room)". The rules for a fixture and a `MIGRATION_M_N` case
are there; this file holds the harness description and how a fixture is built.

## Harness

It lives in `data/src/commonTest/.../local/database/`: `TrailMetricsMigrationTest` (abstract suite)
and `FrozenDatabaseVersions.kt` (one `FrozenDatabaseVersion` per old version, plus
`CURRENT_DATABASE_VERSION`). `TrailMetricsMigrationAndroidHostTest` (Robolectric, platform SQLite,
through the internal `buildRoomDatabase`) and `TrailMetricsMigrationIosTest` (the app's
`getRoomDatabase`, bundled driver) run it in `testAndroidHostTest` and `iosSimulatorArm64Test`. Each
case writes a database file at an old version with plain SQL, outside Room, opens it through the
app's builder pipeline and `appMigrations`, and reads every row back through the DAO. The schema
change procedure around it is in `tm-kmp-shared`, "Changing the database schema (Room)".

## Building the fixture for version M

- `schemaStatements`: copied from `data/schemas/.../M.json`: each entity's `createSql` with
  `${TABLE_NAME}` replaced, then the `setupQueries`.
- Rows: `INSERT` statements in version M's stored form, written as literal text.
- Register it in `frozenDatabaseVersions`. `FrozenDatabaseVersionsSchemaTest` (host only) compares
  the fixture with its schema file.

## Example case name

`` `MIGRATION_1_2 keeps every row and gives note the default` ``: it opens the fixture, asserts
every field of every row at version 2 and the stored `user_version`.
