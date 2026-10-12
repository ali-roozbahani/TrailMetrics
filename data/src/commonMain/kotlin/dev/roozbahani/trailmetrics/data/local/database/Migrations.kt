package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.migration.Migration

/**
 * Every migration of [TrailMetricsDatabase], oldest first. `getRoomDatabase` adds them to the
 * builder, and the migration harness in commonTest opens old databases through the same list.
 * Empty at version 1.
 */
internal val appMigrations: List<Migration> = emptyList()
