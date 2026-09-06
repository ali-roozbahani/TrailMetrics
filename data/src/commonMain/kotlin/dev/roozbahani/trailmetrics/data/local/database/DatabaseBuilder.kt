package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.RoomDatabase
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO

expect fun getDatabaseBuilder(): RoomDatabase.Builder<TrailMetricsDatabase>

fun getRoomDatabase(builder: RoomDatabase.Builder<TrailMetricsDatabase>): TrailMetricsDatabase =
    builder
        .setDriver(BundledSQLiteDriver())
        .setQueryCoroutineContext(Dispatchers.IO)
        .build()
