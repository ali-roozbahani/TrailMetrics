package dev.roozbahani.trailmetrics.domain.model

data class ActivityRecord(
    val id: Long,
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
