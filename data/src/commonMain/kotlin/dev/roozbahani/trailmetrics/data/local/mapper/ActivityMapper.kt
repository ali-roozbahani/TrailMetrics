package dev.roozbahani.trailmetrics.data.local.mapper

import dev.roozbahani.trailmetrics.data.local.entity.ActivityEntity
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord

fun ActivityEntity.toDomain(): ActivityRecord = ActivityRecord(
    id = id,
    activityType = activityType,
    startedAtEpochMillis = startedAtEpochMillis,
    endedAtEpochMillis = endedAtEpochMillis,
    distanceMeters = distanceMeters,
    durationMillis = durationMillis,
    averageSpeedMetersPerSecond = averageSpeedMetersPerSecond,
    calories = calories,
    plannedRoutePoints = plannedRoutePoints,
    actualPath = actualPath,
    snapshotFilePath = snapshotFilePath
)

fun ActivityRecord.toEntity(): ActivityEntity = ActivityEntity(
    id = id,
    activityType = activityType,
    startedAtEpochMillis = startedAtEpochMillis,
    endedAtEpochMillis = endedAtEpochMillis,
    distanceMeters = distanceMeters,
    durationMillis = durationMillis,
    averageSpeedMetersPerSecond = averageSpeedMetersPerSecond,
    calories = calories,
    plannedRoutePoints = plannedRoutePoints,
    actualPath = actualPath,
    snapshotFilePath = snapshotFilePath
)
