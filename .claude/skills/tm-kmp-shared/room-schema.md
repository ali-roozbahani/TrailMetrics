# Changing the database schema (Room)

Moved word for word from `SKILL.md`: the section "Changing the database schema (Room)". The rules are unchanged; they are still cited as `tm-kmp-shared`, "Changing the database schema (Room)".

## Changing the database schema (Room)

Installed apps keep their database file across updates, so an entity or stored-form change must
open every older database and keep its rows. The procedure, in order:

1. Change the entity (`data/src/commonMain/.../local/entity/`) or the converter
   (`local/database/Converters.kt`). A converter's stored form (`ActivityType`'s names, the
   coordinate-list JSON) is pinned in `ConvertersTest`; changing it is a schema change too.
2. Bump `version` in `@Database` (`TrailMetricsDatabase.kt`) from M to N = M + 1, and
   `CURRENT_DATABASE_VERSION` in the harness (`data/src/commonTest/.../local/database/FrozenDatabaseVersions.kt`).
3. Build (`./gradlew :data:testAndroidHostTest`): Room's KSP step exports `data/schemas/.../N.json`.
   Commit it. Never edit, delete or regenerate an existing schema file.
4. Write `MIGRATION_M_N` (a `val` or `object` extending `androidx.room3.migration.Migration`) in
   `data/src/commonMain/.../local/database/Migrations.kt` and add it to `appMigrations`, which
   `getRoomDatabase` adds to the builder. The app and the harness use the same list.
5. Add the frozen fixture of version M (if missing) and the case named for `MIGRATION_M_N`:
   `tm-testing`, "Migration cases (Room)" (`room-migration-rules.md`) is the canonical statement of what they must contain.
6. A destructive step (dropping a table or column, deleting or rewriting rows,
   `fallbackToDestructiveMigration`) and any change of the database file name
   (`DATABASE_FILE_NAME`, pinned by `DatabaseFileNameTest`), its directory or the driver is the
   human's decision: stop and report instead of doing it.
7. The agent never merges a PR that changes the schema or a converter's stored form (owner decisions of
   2026-11-16). Their marks, `data/schemas/`, `Migrations.kt`, `TrailMetricsDatabase.kt` (the `@Database`
   version and entity list) and `Converters.kt` (its stored form exports no schema file and bumps no version,
   yet can make existing data unreadable), are protected paths in `.github/CODEOWNERS`, so such a PR is the
   owner's to merge even when it touches nothing else protected: build it through the gate as usual, post
   the Merge check (condition 6 is "no", `tm-agent-loop`, section 8, `merge.md`) and hand it over. A change of a DAO, a
   mapper, a repository, the builders or a test (`ConvertersTest` included) stays open; an entity change
   reaches the protected files because it needs the bump (step 2).

What catches what: `scripts/check-room-schema.sh --base` (gate and CI, every classification) fails
when an existing schema file is deleted or its `version` or `identityHash` changes (rule (a)), the
version goes down (b), a bump from M to N lacks `N.json`, `MIGRATION_M_N` under
`data/src/commonMain/.../local/database/` or a changed test under
`data/src/commonTest/.../local/database/` that names it (c), the current version has no schema
file (d), or a main source set calls `fallbackToDestructiveMigration` (e). Its
`--check-export-fresh` step after the build fails when the build rewrote or added a file under
`data/schemas/`: an entity change without a bump (step 2). A converter that keeps its column type
does not change the exported schema, so neither check sees a change of its stored form (step 1):
the harness case with a frozen fixture of the old form (step 5) and `tm-pr-review` item 12 catch
it. Both are text and path checks; whether the rows survive is the harness's job (step 5), and
whether its assertions are meaningful the reviewer's.
