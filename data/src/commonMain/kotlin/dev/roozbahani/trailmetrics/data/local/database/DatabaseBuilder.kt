package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.RoomDatabase
import androidx.sqlite.SQLiteDriver
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO

/** The database file name on both platforms; each actual of [getDatabaseBuilder] picks the directory. */
internal const val DATABASE_FILE_NAME = "trailmetrics.db"

expect fun getDatabaseBuilder(): RoomDatabase.Builder<TrailMetricsDatabase>

fun getRoomDatabase(builder: RoomDatabase.Builder<TrailMetricsDatabase>): TrailMetricsDatabase =
    buildRoomDatabase(builder, BundledSQLiteDriver())

// Everything getRoomDatabase does except choosing the driver, so the Android host tests, which
// have no native library for the bundled driver, open a database through the same pipeline.
internal fun buildRoomDatabase(
    builder: RoomDatabase.Builder<TrailMetricsDatabase>,
    driver: SQLiteDriver
): TrailMetricsDatabase =
    builder
        .setDriver(driver)
        .setQueryCoroutineContext(Dispatchers.IO)
        .apply { appMigrations.forEach { addMigrations(it) } }
        .build()
