package dev.roozbahani.trailmetrics.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates

@Entity(tableName = "tbl_activities")
data class ActivityEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val activityType: ActivityType,
    val startedAtEpochMillis: Long,
    val endedAtEpochMillis: Long,
    val distanceMeters: Double,
    val durationMillis: Long,
    val averageSpeedMetersPerSecond: Float?,
    val calories: Double?,
    val plannedRoutePoints: List<Coordinates>,
    val actualPath: List<Coordinates>,
    val snapshotFilePath: String?
)
