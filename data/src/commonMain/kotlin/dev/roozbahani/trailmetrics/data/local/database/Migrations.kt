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

/** Adds the activity type and start time of the in-progress session; the stored rows get NULL (unknown). */
internal val MIGRATION_2_3: Migration = Migration(2, 3) { connection ->
    connection.execSQL("ALTER TABLE `tbl_tracking_session` ADD COLUMN `activityType` TEXT")
    connection.execSQL("ALTER TABLE `tbl_tracking_session` ADD COLUMN `startedAtEpochMillis` INTEGER")
}

/** Adds the table of the route being planned, empty; the other tables are untouched. */
internal val MIGRATION_3_4: Migration = Migration(3, 4) { connection ->
    connection.execSQL(
        "CREATE TABLE IF NOT EXISTS `tbl_route_draft` (`id` INTEGER NOT NULL, `startLatitude` REAL, " +
            "`startLongitude` REAL, `waypoints` TEXT NOT NULL, `generatedRoutePoints` TEXT, " +
            "`generatedRouteDistanceMeters` REAL, `activityType` TEXT NOT NULL, PRIMARY KEY(`id`))"
    )
}

/**
 * Every migration of [TrailMetricsDatabase], oldest first. `getRoomDatabase` adds them to the
 * builder, and the migration harness in commonTest opens old databases through the same list.
 */
internal val appMigrations: List<Migration> = listOf(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4)
