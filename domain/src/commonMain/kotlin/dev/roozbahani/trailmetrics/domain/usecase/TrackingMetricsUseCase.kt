package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator

/** What the tracking screen shows for a [TrackingState]: its [metrics] and the [calories] derived from them. */
data class TrackingMetricsSummary(
    val metrics: TrackingMetrics?,
    val calories: Double?
)

/** The metrics of a session that exists, running, paused or finished; null while idle. */
fun TrackingState.sessionMetrics(): TrackingMetrics? = when (this) {
    is TrackingState.Tracking -> metrics
    is TrackingState.Paused -> metrics
    is TrackingState.Finished -> metrics
    TrackingState.Idle -> null
}

/**
 * The one place that derives the tracking screen's numbers from the session state, for both platforms.
 * Pure: no clock, repository or dispatcher; the profile's weight comes in as an argument.
 */
class TrackingMetricsUseCase(private val calorieCalculator: CalorieCalculator) {

    /**
     * [weightKg] is null while no profile is loaded. The calories are null without a session, without a
     * weight, and while the average speed is unknown (no elapsed time yet).
     */
    operator fun invoke(
        state: TrackingState,
        activityType: ActivityType,
        weightKg: Double?
    ): TrackingMetricsSummary {
        val metrics = state.sessionMetrics()
        val averageSpeed = metrics?.averageSpeedMetersPerSecond
        val calories = if (metrics != null && weightKg != null && averageSpeed != null) {
            calorieCalculator.calculate(
                activityType = activityType,
                averageSpeedMetersPerSecond = averageSpeed,
                weightKg = weightKg,
                durationMillis = metrics.elapsedMillis
            )
        } else {
            null
        }
        return TrackingMetricsSummary(metrics = metrics, calories = calories)
    }
}
