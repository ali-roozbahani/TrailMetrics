package dev.roozbahani.trailmetrics.data.local.database

import androidx.sqlite.SQLiteDriver
import androidx.sqlite.execSQL

/**
 * The `version` of `@Database` in [TrailMetricsDatabase]. A version bump changes it here too, in
 * the same change that adds `N.json`, `MIGRATION_M_N` and its harness case.
 */
internal const val CURRENT_DATABASE_VERSION = 2

/**
 * A database at an old version, written with plain SQL outside Room, the way Room itself wrote a
 * fresh database at that version: [schemaStatements] are the entities' `createSql` (table name
 * substituted) and the `setupQueries` of `data/schemas/.../<version>.json`, followed by
 * `PRAGMA user_version`. [rowStatements] insert rows in the stored form of that version, written
 * literally, never through the current converters.
 *
 * Frozen: a fixture never changes once its version has shipped. A version bump M to N adds the
 * fixture of version M here if it is missing, and a case for `MIGRATION_M_N` in
 * [TrailMetricsMigrationTest].
 */
internal class FrozenDatabaseVersion(
    val version: Int,
    val identityHash: String,
    val schemaStatements: List<String>,
    val rowStatements: List<String>,
) {
    fun writeTo(driver: SQLiteDriver, path: String) {
        val connection = driver.open(path)
        try {
            (schemaStatements + rowStatements).forEach { connection.execSQL(it) }
            connection.execSQL("PRAGMA user_version = $version")
        } finally {
            connection.close()
        }
    }
}

internal val databaseVersion1 = FrozenDatabaseVersion(
    version = 1,
    identityHash = "37e36675b03f9e9c12d81000dd6c1408",
    schemaStatements = listOf(
        "CREATE TABLE IF NOT EXISTS `tbl_activities` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
            "`activityType` TEXT NOT NULL, `startedAtEpochMillis` INTEGER NOT NULL, " +
            "`endedAtEpochMillis` INTEGER NOT NULL, `distanceMeters` REAL NOT NULL, " +
            "`durationMillis` INTEGER NOT NULL, `averageSpeedMetersPerSecond` REAL, `calories` REAL, " +
            "`plannedRoutePoints` TEXT NOT NULL, `actualPath` TEXT NOT NULL, `snapshotFilePath` TEXT)",
        "CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)",
        "INSERT OR REPLACE INTO room_master_table (id,identity_hash) " +
            "VALUES(42, '37e36675b03f9e9c12d81000dd6c1408')",
    ),
    rowStatements = listOf(
        // Every optional column set, two non-empty coordinate lists.
        "INSERT INTO tbl_activities VALUES (1, 'Running', 1700000000000, 1700001800000, 5012.5, " +
            "1800000, 2.75, 412.5, " +
            "'[{\"latitude\":51.336,\"longitude\":12.388},{\"latitude\":51.337,\"longitude\":12.389}]', " +
            "'[{\"latitude\":51.336,\"longitude\":12.388},{\"latitude\":51.3365,\"longitude\":12.3885}," +
            "{\"latitude\":51.337,\"longitude\":12.389}]', " +
            "'/snapshots/activity-1.png')",
        // Every optional column null, an empty planned route.
        "INSERT INTO tbl_activities VALUES (2, 'Cycling', 1700100000000, 1700103600000, 30250.0, " +
            "3600000, NULL, NULL, '[]', " +
            "'[{\"latitude\":-33.8688,\"longitude\":151.2093},{\"latitude\":-33.87,\"longitude\":151.21}]', " +
            "NULL)",
        // A gap in the ids, mixed optional columns, an empty path.
        "INSERT INTO tbl_activities VALUES (7, 'Walking', 1700200000000, 1700200900000, 1100.25, " +
            "900000, 1.25, NULL, '[{\"latitude\":48.1374,\"longitude\":11.5755}]', '[]', " +
            "'/snapshots/activity-7.png')",
    ),
)

/** Every frozen fixture, oldest first; the host test checks each one against its schema file. */
internal val frozenDatabaseVersions: List<FrozenDatabaseVersion> = listOf(databaseVersion1)
