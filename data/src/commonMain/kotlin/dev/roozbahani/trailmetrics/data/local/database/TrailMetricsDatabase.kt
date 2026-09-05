package dev.roozbahani.trailmetrics.data.local.database

import androidx.room.ConstructedBy
import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.RoomDatabaseConstructor
import androidx.room.TypeConverters
import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.entity.ActivityEntity

@Database(
    entities = [ActivityEntity::class],
    version = 1,
    exportSchema = true
)
@TypeConverters(Converters::class)
@ConstructedBy(TrailMetricsDatabaseConstructor::class)
abstract class TrailMetricsDatabase : RoomDatabase() {
    abstract fun activityDao(): ActivityDao
}

expect object TrailMetricsDatabaseConstructor : RoomDatabaseConstructor<TrailMetricsDatabase> {
    override fun initialize(): TrailMetricsDatabase
}
