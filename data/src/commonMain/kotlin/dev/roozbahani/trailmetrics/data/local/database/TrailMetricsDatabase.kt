package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.ConstructedBy
import androidx.room3.Database
import androidx.room3.RoomDatabase
import androidx.room3.RoomDatabaseConstructor
import androidx.room3.ColumnTypeConverters
import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.entity.ActivityEntity

@Database(
    entities = [ActivityEntity::class],
    version = 1,
    exportSchema = true
)
@ColumnTypeConverters(Converters::class)
@ConstructedBy(TrailMetricsDatabaseConstructor::class)
abstract class TrailMetricsDatabase : RoomDatabase() {
    abstract fun activityDao(): ActivityDao
}

expect object TrailMetricsDatabaseConstructor : RoomDatabaseConstructor<TrailMetricsDatabase> {
    override fun initialize(): TrailMetricsDatabase
}
