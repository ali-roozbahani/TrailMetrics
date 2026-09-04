package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock

class SaveActivityUseCase(
    private val activityHistoryRepository: ActivityHistoryRepository,
    private val calorieCalculator: CalorieCalculator,
    private val clock: Clock
) {
    suspend operator fun invoke(
        activityType: ActivityType,
        plannedRoutePoints: List<Coordinates>,
        metrics: TrackingMetrics,
        weightKg: Double,
        startedAtEpochMillis: Long,
        snapshotFilePath: String?
    ): Long {
        val calories = metrics.averageSpeedMetersPerSecond?.let { averageSpeed ->
            calorieCalculator.calculate(
                activityType = activityType,
                averageSpeedMetersPerSecond = averageSpeed,
                weightKg = weightKg,
                durationMillis = metrics.elapsedMillis
            )
        }

        val record = ActivityRecord(
            id = 0,
            activityType = activityType,
            startedAtEpochMillis = startedAtEpochMillis,
            endedAtEpochMillis = clock.nowMillis(),
            distanceMeters = metrics.distanceMeters,
            durationMillis = metrics.elapsedMillis,
            averageSpeedMetersPerSecond = metrics.averageSpeedMetersPerSecond,
            calories = calories,
            plannedRoutePoints = plannedRoutePoints,
            actualPath = metrics.path,
            snapshotFilePath = snapshotFilePath
        )

        return activityHistoryRepository.saveActivity(record)
    }
}
