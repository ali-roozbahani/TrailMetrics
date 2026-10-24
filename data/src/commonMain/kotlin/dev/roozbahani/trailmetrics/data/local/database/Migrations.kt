package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.migration.Migration
import androidx.sqlite.execSQL

/** Adds the two tables of the in-progress tracking session; `tbl_activities` is untouched. */
internal val MIGRATION_1_2: Migration = Migration(1, 2) { connection ->
    connection.execSQL(
        "CREATE TABLE IF NOT EXISTS `tbl_tracking_session` (`id` INTEGER NOT NULL, " +
            "`stateKind` TEXT NOT NULL, `elapsedMillis` INTEGER NOT NULL, " +
            "`lastUpdateElapsedRealtimeMillis` INTEGER NOT NULL, `distanceMeters` REAL NOT NULL, " +
            "`currentSpeedMetersPerSecond` REAL, `savedAtEpochMillis` INTEGER NOT NULL, PRIMARY KEY(`id`))"
    )
    connection.execSQL(
        "CREATE TABLE IF NOT EXISTS `tbl_tracking_session_points` (`sessionId` INTEGER NOT NULL, " +
            "`sequence` INTEGER NOT NULL, `latitude` REAL NOT NULL, `longitude` REAL NOT NULL, " +
            "PRIMARY KEY(`sessionId`, `sequence`))"
    )
}

/**
 * Every migration of [TrailMetricsDatabase], oldest first. `getRoomDatabase` adds them to the
 * builder, and the migration harness in commonTest opens old databases through the same list.
 */
internal val appMigrations: List<Migration> = listOf(MIGRATION_1_2)
