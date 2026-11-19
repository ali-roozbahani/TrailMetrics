package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class TrackingMetricsUseCaseTest {
    private val useCase = TrackingMetricsUseCase(CalorieCalculator())

    private val metrics = TrackingMetrics(
        elapsedMillis = 600_000L,
        lastUpdateElapsedRealtimeMillis = 600_000L,
        distanceMeters = 1_000.0,
        path = listOf(Coordinates(1.0, 1.0), Coordinates(1.1, 1.1))
    )

    private fun sessionStates(m: TrackingMetrics) = listOf(
        TrackingState.Tracking(m),
        TrackingState.Paused(m),
        TrackingState.Finished(m)
    )

    @Test
    fun `idle has no metrics and no calories with or without a profile`() {
        assertEquals(
            TrackingMetricsSummary(metrics = null, calories = null),
            useCase(TrackingState.Idle, ActivityType.Walking, weightKg = 70.0)
        )
        assertEquals(
            TrackingMetricsSummary(metrics = null, calories = null),
            useCase(TrackingState.Idle, ActivityType.Walking, weightKg = null)
        )
    }

    @Test
    fun `tracking and paused and finished carry the metrics of the session`() {
        for (state in sessionStates(metrics)) {
            assertEquals(metrics, useCase(state, ActivityType.Walking, weightKg = 70.0).metrics, "for $state")
            assertEquals(metrics, state.sessionMetrics(), "for $state")
        }
        assertNull(TrackingState.Idle.sessionMetrics())
    }

    @Test
    fun `calories follow the calorie calculator from the profile weight and the average speed and the duration`() {
        // 1000 m in 600 s is 6 km/h, walking MET 5.0: 5.0 * 70 kg * (600 s / 3600 s) = 58.33 kcal.
        for (state in sessionStates(metrics)) {
            val calories = assertNotNull(useCase(state, ActivityType.Walking, weightKg = 70.0).calories, "for $state")
            assertEquals(58.33, calories, 0.01, "for $state")
        }
        val cycling = assertNotNull(useCase(TrackingState.Tracking(metrics), ActivityType.Cycling, 70.0).calories)
        assertEquals(
            CalorieCalculator().calculate(ActivityType.Cycling, metrics.averageSpeedMetersPerSecond!!, 70.0, 600_000L),
            cycling
        )
    }

    @Test
    fun `calories use the activity type`() {
        val state = TrackingState.Tracking(metrics)

        assertNotEquals(
            useCase(state, ActivityType.Cycling, weightKg = 70.0).calories,
            useCase(state, ActivityType.Running, weightKg = 70.0).calories
        )
    }

    @Test
    fun `calories are null without a profile and the metrics are still there`() {
        for (state in sessionStates(metrics)) {
            val summary = useCase(state, ActivityType.Walking, weightKg = null)

            assertEquals(metrics, summary.metrics, "for $state")
            assertNull(summary.calories, "for $state")
        }
    }

    @Test
    fun `calories are null while the average speed is unknown`() {
        val noTimeYet = metrics.copy(elapsedMillis = 0L, distanceMeters = 0.0)
        for (state in sessionStates(noTimeYet)) {
            val summary = useCase(state, ActivityType.Walking, weightKg = 70.0)

            assertEquals(noTimeYet, summary.metrics, "for $state")
            assertNull(summary.calories, "for $state")
        }
    }
}
