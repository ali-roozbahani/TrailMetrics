package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingEvent
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.distanceTo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class UpdateTrackingStateUseCaseTest {

    private val useCase = UpdateTrackingStateUseCase()
    private val point1 = Coordinates(51.33636378506572, 12.388521734194189)
    private val point2 = Coordinates(51.3279709867728, 12.394637438461285)

    @Test
    fun `start from Idle transitions to Tracking with fresh metrics`() {
        val idleState = TrackingState.Idle
        val startEvent = TrackingEvent.Start(point1, 0)

        var newState = useCase(idleState, startEvent)
        assertIs<TrackingState.Tracking>(newState)

        newState = newState as TrackingState.Tracking
        val expectedPath = listOf(point1)
        assertTrue(newState.metrics.path.size == expectedPath.size && newState.metrics.path.containsAll(expectedPath))
        assertEquals(0, newState.metrics.elapsedMillis)
        assertEquals(0, newState.metrics.lastUpdateTimestampMillis)
        assertEquals(0.0, newState.metrics.distanceMeters, absoluteTolerance = 1.0)
    }

    @Test
    fun `start from Finished transitions to Tracking with fresh metrics`() {
        val currentState = TrackingState.Finished(sampleMetrics())
        val startEvent = TrackingEvent.Start(point1, 0)

        var newState = useCase(currentState, startEvent)
        assertIs<TrackingState.Tracking>(newState)

        newState = newState as TrackingState.Tracking
        val expectedPath = listOf(point1)
        assertTrue(newState.metrics.path.size == expectedPath.size && newState.metrics.path.containsAll(expectedPath))
        assertEquals(0, newState.metrics.elapsedMillis)
        assertEquals(0, newState.metrics.lastUpdateTimestampMillis)
        assertEquals(0.0, newState.metrics.distanceMeters, absoluteTolerance = 1.0)
    }

    @Test
    fun `pause from Tracking transitions to Paused without changing metrics`() {
        val metrics = sampleMetrics()
        val currentState = TrackingState.Tracking(metrics = metrics)
        val pauseEvent = TrackingEvent.Pause(timestampMillis = 15)

        var newState = useCase(currentState, pauseEvent)
        assertIs<TrackingState.Paused>(newState)

        newState = newState as TrackingState.Paused
        assertEquals(metrics, newState.metrics)
    }

    @Test
    fun `resume from Paused transitions to Tracking and updates lastUpdateTimestampMillis`() {
        val pausedStateMetrics = sampleMetrics()
        val pausedState = TrackingState.Paused(pausedStateMetrics)

        val resumeEvent = TrackingEvent.Resume(20)
        var newState = useCase(pausedState, resumeEvent)
        assertIs<TrackingState.Tracking>(newState)

        newState = newState as TrackingState.Tracking
        assertEquals(resumeEvent.timestampMillis, newState.metrics.lastUpdateTimestampMillis) // must be 20 as defined above
        assertEquals(pausedStateMetrics.path, newState.metrics.path)
        assertEquals(pausedStateMetrics.elapsedMillis, newState.metrics.elapsedMillis)
        assertEquals(pausedState.metrics.distanceMeters, newState.metrics.distanceMeters)
    }

    @Test
    fun `pause is ignored when current state is Idle`() {
        val idleState = TrackingState.Idle

        val newState = useCase(idleState, TrackingEvent.Pause(10))
        assertEquals(TrackingState.Idle, newState)
    }

    @Test
    fun `locationReceived is ignored when current state is Paused`() {
        val pausedMetrics = sampleMetrics()
        val currentState = TrackingState.Paused(pausedMetrics)
        val locationReceivedEvent = TrackingEvent.LocationReceived(
            coordinates = point2,
            timestampMillis = 15,
            speedMetersPerSecond = null
        )

        val newState = useCase(currentState, locationReceivedEvent)

        assertIs<TrackingState.Paused>(newState)
        assertEquals(pausedMetrics, newState.metrics)
    }

    @Test
    fun `locationReceived from Tracking updates distance and elapsed time and path`() {
        val currentState = TrackingState.Tracking(sampleMetrics())
        val newUpdateEvent = TrackingEvent.LocationReceived(
            coordinates = point2,
            timestampMillis = 20,
            speedMetersPerSecond = null
        )
        val distanceMeters = currentState.metrics.path.last().distanceTo(newUpdateEvent.coordinates)
        val deltaTime = newUpdateEvent.timestampMillis - currentState.metrics.lastUpdateTimestampMillis

        var newState = useCase(currentState, newUpdateEvent)
        assertIs<TrackingState.Tracking>(newState)

        newState = newState as TrackingState.Tracking
        assertEquals(currentState.metrics.distanceMeters + distanceMeters, newState.metrics.distanceMeters)
        assertEquals(currentState.metrics.elapsedMillis + deltaTime, newState.metrics.elapsedMillis)
        assertEquals(2, newState.metrics.path.size)
        val expectedPath = listOf(point1, point2)
        assertTrue(newState.metrics.path.size == expectedPath.size && newState.metrics.path.containsAll(expectedPath))
        assertEquals(newUpdateEvent.timestampMillis, newState.metrics.lastUpdateTimestampMillis)
    }

    @Test
    fun `stop from Tracking transitions to Finished`() {
        val currentState = TrackingState.Tracking(sampleMetrics())
        val stopEvent = TrackingEvent.Stop(currentState.metrics.lastUpdateTimestampMillis + 10)

        val newState = useCase(currentState, stopEvent)

        assertIs<TrackingState.Finished>(newState)
        assertEquals(currentState.metrics, newState.metrics)
    }

    @Test
    fun `stop from Paused transitions to Finished`() {
        val currentState = TrackingState.Paused(sampleMetrics())
        val stopEvent = TrackingEvent.Stop(currentState.metrics.lastUpdateTimestampMillis + 10)

        val newState = useCase(currentState, stopEvent)

        assertIs<TrackingState.Finished>(newState)
        assertEquals(currentState.metrics, newState.metrics)
    }

    @Test
    fun `start is ignored when current state is Tracking`() {
        val trackingState = TrackingState.Tracking(sampleMetrics())
        val startEvent = TrackingEvent.Start(point2, 30)

        val newState = useCase(trackingState, startEvent)

        assertEquals(trackingState, newState)
    }

    @Test
    fun `locationReceived is ignored when current state is Idle`() {
        val idleState = TrackingState.Idle
        val locationReceivedEvent = TrackingEvent.LocationReceived(
            coordinates = point1,
            timestampMillis = 10,
            speedMetersPerSecond = null
        )

        val newState = useCase(idleState, locationReceivedEvent)

        assertEquals(idleState, newState)
    }

    private fun sampleMetrics(
        elapsedMillis: Long = 10,
        lastUpdateTimestampMillis: Long = 10,
        distanceMeters: Double = 100.0,
        path: List<Coordinates> = listOf(point1)
    ) = TrackingMetrics(
        elapsedMillis = elapsedMillis,
        lastUpdateTimestampMillis = lastUpdateTimestampMillis,
        distanceMeters = distanceMeters,
        path = path
    )
}
