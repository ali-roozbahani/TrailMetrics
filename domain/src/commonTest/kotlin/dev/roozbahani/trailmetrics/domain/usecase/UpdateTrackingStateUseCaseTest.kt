package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingEvent
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.distanceTo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertSame
import kotlin.test.assertTrue

class UpdateTrackingStateUseCaseTest {

    private val useCase = UpdateTrackingStateUseCase()
    private val point1 = Coordinates(51.33636378506572, 12.388521734194189)
    private val point2 = Coordinates(51.3279709867728, 12.394637438461285)

    @Test
    fun `start from Idle transitions to Tracking with fresh metrics`() {
        val idleState = TrackingState.Idle
        val startEvent = TrackingEvent.Start(point1, 0)

        val newState = useCase(idleState, startEvent)
        assertIs<TrackingState.Tracking>(newState)

        val expectedPath = listOf(point1)
        assertTrue(newState.metrics.path.size == expectedPath.size && newState.metrics.path.containsAll(expectedPath))
        assertEquals(0, newState.metrics.elapsedMillis)
        assertEquals(0, newState.metrics.lastUpdateElapsedRealtimeMillis)
        assertEquals(0.0, newState.metrics.distanceMeters, absoluteTolerance = 1.0)
    }

    @Test
    fun `start from Finished transitions to Tracking with fresh metrics`() {
        val currentState = TrackingState.Finished(sampleMetrics())
        val startEvent = TrackingEvent.Start(point1, 0)

        val newState = useCase(currentState, startEvent)
        assertIs<TrackingState.Tracking>(newState)

        val expectedPath = listOf(point1)
        assertTrue(newState.metrics.path.size == expectedPath.size && newState.metrics.path.containsAll(expectedPath))
        assertEquals(0, newState.metrics.elapsedMillis)
        assertEquals(0, newState.metrics.lastUpdateElapsedRealtimeMillis)
        assertEquals(0.0, newState.metrics.distanceMeters, absoluteTolerance = 1.0)
    }

    @Test
    fun `pause from Tracking transitions to Paused without changing metrics`() {
        val metrics = sampleMetrics()
        val currentState = TrackingState.Tracking(metrics = metrics)
        val pauseEvent = TrackingEvent.Pause(elapsedRealtimeMillis = 15)

        val newState = useCase(currentState, pauseEvent)
        assertIs<TrackingState.Paused>(newState)

        assertEquals(metrics, newState.metrics)
    }

    @Test
    fun `resume from Paused transitions to Tracking and updates lastUpdateElapsedRealtimeMillis`() {
        val pausedStateMetrics = sampleMetrics()
        val pausedState = TrackingState.Paused(pausedStateMetrics)

        val resumeEvent = TrackingEvent.Resume(20)
        val newState = useCase(pausedState, resumeEvent)
        assertIs<TrackingState.Tracking>(newState)

        assertEquals(resumeEvent.elapsedRealtimeMillis, newState.metrics.lastUpdateElapsedRealtimeMillis) // must be 20 as defined above
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
            elapsedRealtimeMillis = 15,
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
            elapsedRealtimeMillis = 20,
            speedMetersPerSecond = null
        )
        val distanceMeters = currentState.metrics.path.last().distanceTo(newUpdateEvent.coordinates)
        val deltaTime = newUpdateEvent.elapsedRealtimeMillis - currentState.metrics.lastUpdateElapsedRealtimeMillis

        val newState = useCase(currentState, newUpdateEvent)
        assertIs<TrackingState.Tracking>(newState)

        assertEquals(currentState.metrics.distanceMeters + distanceMeters, newState.metrics.distanceMeters)
        assertEquals(currentState.metrics.elapsedMillis + deltaTime, newState.metrics.elapsedMillis)
        assertEquals(2, newState.metrics.path.size)
        val expectedPath = listOf(point1, point2)
        assertTrue(newState.metrics.path.size == expectedPath.size && newState.metrics.path.containsAll(expectedPath))
        assertEquals(newUpdateEvent.elapsedRealtimeMillis, newState.metrics.lastUpdateElapsedRealtimeMillis)
    }

    @Test
    fun `stop from Tracking transitions to Finished`() {
        val currentState = TrackingState.Tracking(sampleMetrics())
        val stopEvent = TrackingEvent.Stop(currentState.metrics.lastUpdateElapsedRealtimeMillis + 10)

        val newState = useCase(currentState, stopEvent)

        assertIs<TrackingState.Finished>(newState)
        assertEquals(currentState.metrics, newState.metrics)
    }

    @Test
    fun `stop from Paused transitions to Finished`() {
        val currentState = TrackingState.Paused(sampleMetrics())
        val stopEvent = TrackingEvent.Stop(currentState.metrics.lastUpdateElapsedRealtimeMillis + 10)

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
            elapsedRealtimeMillis = 10,
            speedMetersPerSecond = null
        )

        val newState = useCase(idleState, locationReceivedEvent)

        assertEquals(idleState, newState)
    }

    @Test
    fun `start is ignored when current state is Paused`() {
        val pausedState = TrackingState.Paused(sampleMetrics())

        assertSame(pausedState, useCase(pausedState, TrackingEvent.Start(point2, 30)))
    }

    @Test
    fun `pause is ignored when current state is not Tracking`() {
        listOf(TrackingState.Paused(sampleMetrics()), TrackingState.Finished(sampleMetrics())).forEach { state ->
            assertSame(state, useCase(state, TrackingEvent.Pause(30)), "Pause from $state")
        }
    }

    @Test
    fun `resume is ignored when current state is not Paused`() {
        val states = listOf(
            TrackingState.Idle,
            TrackingState.Tracking(sampleMetrics()),
            TrackingState.Finished(sampleMetrics())
        )

        states.forEach { state ->
            assertSame(state, useCase(state, TrackingEvent.Resume(30)), "Resume from $state")
        }
    }

    @Test
    fun `stop is ignored when current state is Idle or Finished`() {
        listOf(TrackingState.Idle, TrackingState.Finished(sampleMetrics())).forEach { state ->
            assertSame(state, useCase(state, TrackingEvent.Stop(30)), "Stop from $state")
        }
    }

    @Test
    fun `locationReceived is ignored when current state is Finished`() {
        val finishedState = TrackingState.Finished(sampleMetrics())
        val locationReceivedEvent = TrackingEvent.LocationReceived(
            coordinates = point2,
            elapsedRealtimeMillis = 30,
            speedMetersPerSecond = 2f
        )

        assertSame(finishedState, useCase(finishedState, locationReceivedEvent))
    }

    @Test
    fun `locationReceived earlier than the last update adds no time and re-bases the last update`() {
        val currentState = TrackingState.Tracking(sampleMetrics(elapsedMillis = 5_000, lastUpdateElapsedRealtimeMillis = 10_000))
        val earlierEvent = TrackingEvent.LocationReceived(
            coordinates = point2,
            elapsedRealtimeMillis = 7_000,
            speedMetersPerSecond = null
        )

        val rebased = useCase(currentState, earlierEvent)
        assertIs<TrackingState.Tracking>(rebased)
        assertEquals(5_000, rebased.metrics.elapsedMillis)
        assertEquals(7_000, rebased.metrics.lastUpdateElapsedRealtimeMillis)

        val nextEvent = TrackingEvent.LocationReceived(
            coordinates = point1,
            elapsedRealtimeMillis = 9_000,
            speedMetersPerSecond = null
        )
        val next = useCase(rebased, nextEvent)
        assertIs<TrackingState.Tracking>(next)
        // 5_000 + (9_000 - 7_000)
        assertEquals(7_000, next.metrics.elapsedMillis)
        assertEquals(9_000, next.metrics.lastUpdateElapsedRealtimeMillis)
    }

    private fun sampleMetrics(
        elapsedMillis: Long = 10,
        lastUpdateElapsedRealtimeMillis: Long = 10,
        distanceMeters: Double = 100.0,
        path: List<Coordinates> = listOf(point1)
    ) = TrackingMetrics(
        elapsedMillis = elapsedMillis,
        lastUpdateElapsedRealtimeMillis = lastUpdateElapsedRealtimeMillis,
        distanceMeters = distanceMeters,
        path = path
    )
}
