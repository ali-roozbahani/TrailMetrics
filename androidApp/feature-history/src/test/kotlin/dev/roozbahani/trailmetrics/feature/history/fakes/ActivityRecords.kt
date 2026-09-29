package dev.roozbahani.trailmetrics.feature.history.fakes

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates

fun activityRecord(id: Long, snapshotFilePath: String? = null) = ActivityRecord(
    id = id,
    activityType = ActivityType.Running,
    startedAtEpochMillis = 1_700_000_000_000L + id,
    endedAtEpochMillis = 1_700_000_600_000L + id,
    distanceMeters = 1_000.0 * id,
    durationMillis = 600_000L,
    averageSpeedMetersPerSecond = 2.5f,
    calories = 120.0,
    plannedRoutePoints = listOf(Coordinates(latitude = 52.52, longitude = 13.405)),
    actualPath = listOf(
        Coordinates(latitude = 52.52, longitude = 13.405),
        Coordinates(latitude = 52.523, longitude = 13.401)
    ),
    snapshotFilePath = snapshotFilePath
)
