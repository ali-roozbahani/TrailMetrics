package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.ConstructedBy
import androidx.room3.Database
import androidx.room3.RoomDatabase
import androidx.room3.RoomDatabaseConstructor
import androidx.room3.ColumnTypeConverters
import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionDao
import dev.roozbahani.trailmetrics.data.local.entity.ActivityEntity
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionPointEntity

@Database(
    entities = [ActivityEntity::class, TrackingSessionEntity::class, TrackingSessionPointEntity::class],
    version = 3,
    exportSchema = true
)
@ColumnTypeConverters(Converters::class)
@ConstructedBy(TrailMetricsDatabaseConstructor::class)
abstract class TrailMetricsDatabase : RoomDatabase() {
    abstract fun activityDao(): ActivityDao
    abstract fun trackingSessionDao(): TrackingSessionDao
}

expect object TrailMetricsDatabaseConstructor : RoomDatabaseConstructor<TrailMetricsDatabase> {
    override fun initialize(): TrailMetricsDatabase
}
