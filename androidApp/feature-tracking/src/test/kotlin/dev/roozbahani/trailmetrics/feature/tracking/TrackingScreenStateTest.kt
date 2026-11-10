package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/** The derived properties of [TrackingScreenState], for every domain [TrackingState]. */
class TrackingScreenStateTest {

    private fun <T> assertForEveryState(expected: Map<TrackingState, T>, property: (TrackingScreenState) -> T) {
        assertEquals(ALL_STATES.toSet(), expected.keys, "the table must cover every TrackingState")
        expected.forEach { (trackingState, value) ->
            assertEquals(value, property(TrackingScreenState(trackingState = trackingState)), "for $trackingState")
        }
    }

    @Test
    fun `currentPath is the session path once a session exists and empty while idle`() {
        assertForEveryState(
            mapOf(IDLE to emptyList(), TRACKING to PATH, PAUSED to PATH, FINISHED to PATH)
        ) { it.currentPath }
    }

    @Test
    fun `recordedPathToDraw is empty for an empty path and for a one-point path`() {
        assertEquals(emptyList(), TrackingScreenState().recordedPathToDraw)
        val onePoint = TrackingScreenState(trackingState = TrackingState.Tracking(metricsOf(PATH.take(1))))
        assertEquals(emptyList(), onePoint.recordedPathToDraw)
    }

    @Test
    fun `recordedPathToDraw is the path from two points on, also for a restored paused or finished session`() {
        val twoPoints = TrackingState.Tracking(metricsOf(PATH))
        assertEquals(PATH, TrackingScreenState(trackingState = twoPoints).recordedPathToDraw)
        assertForEveryState(
            mapOf(IDLE to emptyList(), TRACKING to PATH, PAUSED to PATH, FINISHED to PATH)
        ) { it.recordedPathToDraw }
    }

    @Test
    fun `recordedPathToDraw does not depend on a planned route`() {
        val state = TrackingScreenState(trackingState = PAUSED, plannedRoutePoints = emptyList(), routeProgress = null)
        assertEquals(PATH, state.recordedPathToDraw)
    }

    @Test
    fun `camera does nothing for an empty path`() {
        assertEquals(CameraPlan.None, cameraPlanFor(emptyList(), pathAlreadySeen = false))
        assertEquals(CameraPlan.None, cameraPlanFor(emptyList(), pathAlreadySeen = true))
    }

    @Test
    fun `camera follows the first point of a live session`() {
        assertEquals(CameraPlan.FollowLastPoint, cameraPlanFor(PATH.take(1), pathAlreadySeen = false))
    }

    @Test
    fun `camera fits a path of two or more points once, when it is the first path seen`() {
        assertEquals(CameraPlan.FitPath, cameraPlanFor(PATH, pathAlreadySeen = false))
    }

    @Test
    fun `camera follows the last point once a path was seen, so a live session is never fitted`() {
        assertEquals(CameraPlan.FollowLastPoint, cameraPlanFor(PATH, pathAlreadySeen = true))
        assertEquals(CameraPlan.FollowLastPoint, cameraPlanFor(PATH.take(1), pathAlreadySeen = true))
    }

    @Test
    fun `currentMetrics are the session metrics once a session exists and null while idle`() {
        assertForEveryState(
            mapOf(IDLE to null, TRACKING to METRICS, PAUSED to METRICS, FINISHED to METRICS)
        ) { it.currentMetrics }
    }

    @Test
    fun `canStart is true only when idle`() {
        assertForEveryState(mapOf(IDLE to true, TRACKING to false, PAUSED to false, FINISHED to false)) { it.canStart }
    }

    @Test
    fun `canStart is false in every state while the stored session is loading`() {
        ALL_STATES.forEach { trackingState ->
            val state = TrackingScreenState(trackingState = trackingState, isRestoring = true)
            assertFalse(state.canStart, "for $trackingState")
        }
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

    private fun metricsOf(path: List<Coordinates>) = METRICS.copy(path = path)

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

        val IDLE: TrackingState = TrackingState.Idle
        val TRACKING: TrackingState = TrackingState.Tracking(METRICS)
        val PAUSED: TrackingState = TrackingState.Paused(METRICS)
        val FINISHED: TrackingState = TrackingState.Finished(METRICS)
        val ALL_STATES = listOf(IDLE, TRACKING, PAUSED, FINISHED)
    }
}
