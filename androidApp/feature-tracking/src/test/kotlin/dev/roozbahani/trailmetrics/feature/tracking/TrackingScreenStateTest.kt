package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import org.junit.Test
import kotlin.test.assertEquals

/** The derived properties of [TrackingScreenState], for every domain [TrackingState]. */
class TrackingScreenStateTest {

    private fun <T> assertForEveryState(expected: Map<TrackingState, T>, property: (TrackingScreenState) -> T) {
        assertEquals(ALL_STATES.toSet(), expected.keys, "the table must cover every TrackingState")
        expected.forEach { (trackingState, value) ->
            assertEquals(value, property(TrackingScreenState(trackingState = trackingState)), "for $trackingState")
        }
    }

    @Test
    fun `currentPath is the session path while tracking or paused and empty otherwise`() {
        assertForEveryState(
            mapOf(IDLE to emptyList(), TRACKING to PATH, PAUSED to PATH, FINISHED to emptyList())
        ) { it.currentPath }
    }

    @Test
    fun `currentMetrics are the session metrics while tracking or paused and null otherwise`() {
        assertForEveryState(
            mapOf(IDLE to null, TRACKING to METRICS, PAUSED to METRICS, FINISHED to null)
        ) { it.currentMetrics }
    }

    @Test
    fun `canStart is true only when idle or finished`() {
        assertForEveryState(mapOf(IDLE to true, TRACKING to false, PAUSED to false, FINISHED to true)) { it.canStart }
    }

    @Test
    fun `canPause is true only while tracking`() {
        assertForEveryState(mapOf(IDLE to false, TRACKING to true, PAUSED to false, FINISHED to false)) { it.canPause }
    }

    @Test
    fun `canResume is true only while paused`() {
        assertForEveryState(mapOf(IDLE to false, TRACKING to false, PAUSED to true, FINISHED to false)) { it.canResume }
    }

    @Test
    fun `canStop is true only while tracking or paused`() {
        assertForEveryState(mapOf(IDLE to false, TRACKING to true, PAUSED to true, FINISHED to false)) { it.canStop }
    }

    private companion object {
        val PATH = listOf(
            Coordinates(latitude = 52.000, longitude = 13.000),
            Coordinates(latitude = 52.001, longitude = 13.000)
        )
        val METRICS = TrackingMetrics(
            elapsedMillis = 60_000L,
            lastUpdateElapsedRealtimeMillis = 60_000L,
            distanceMeters = 111.0,
            path = PATH
        )

        /** Finished carries metrics too, so an empty path there comes from the mapping, not the data. */
        val IDLE: TrackingState = TrackingState.Idle
        val TRACKING: TrackingState = TrackingState.Tracking(METRICS)
        val PAUSED: TrackingState = TrackingState.Paused(METRICS)
        val FINISHED: TrackingState = TrackingState.Finished(METRICS)
        val ALL_STATES = listOf(IDLE, TRACKING, PAUSED, FINISHED)
    }
}
