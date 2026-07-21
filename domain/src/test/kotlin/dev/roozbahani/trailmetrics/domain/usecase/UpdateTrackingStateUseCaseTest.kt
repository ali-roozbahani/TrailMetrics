package dev.roozbahani.trailmetrics.domain.usecase

import com.google.common.truth.Truth.assertThat
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingEvent
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.distanceTo
import org.junit.Test

class UpdateTrackingStateUseCaseTest {

    private val useCase = UpdateTrackingStateUseCase()
    private val point1 = Coordinates(51.33636378506572, 12.388521734194189)
    private val point2 = Coordinates(51.3279709867728, 12.394637438461285)

    @Test
    fun `start from Idle transitions to Tracking with fresh metrics`() {
        val idleState = TrackingState.Idle
        val startEvent = TrackingEvent.Start(point1, 0)

        var newState = useCase(idleState, startEvent)
        assertThat(newState).isInstanceOf(TrackingState.Tracking::class.java)

        newState = newState as TrackingState.Tracking
        assertThat(newState.metrics.path).containsExactly(point1)
        assertThat(newState.metrics.elapsedMillis).isEqualTo(0)
        assertThat(newState.metrics.lastUpdateTimestampMillis).isEqualTo(0)
        assertThat(newState.metrics.distanceMeters).isWithin(1.0).of(0.0)
    }

    @Test
    fun `start from Finished transitions to Tracking with fresh metrics`() {
        val currentState = TrackingState.Finished(sampleMetrics())
        val startEvent = TrackingEvent.Start(point1, 0)

        var newState = useCase(currentState, startEvent)
        assertThat(newState).isInstanceOf(TrackingState.Tracking::class.java)

        newState = newState as TrackingState.Tracking
        assertThat(newState.metrics.path).containsExactly(point1)
        assertThat(newState.metrics.elapsedMillis).isEqualTo(0)
        assertThat(newState.metrics.lastUpdateTimestampMillis).isEqualTo(0)
        assertThat(newState.metrics.distanceMeters).isWithin(1.0).of(0.0)
    }

    @Test
    fun `pause from Tracking transitions to Paused without changing metrics`() {
        val metrics = sampleMetrics()
        val currentState = TrackingState.Tracking(metrics = metrics)
        val pauseEvent = TrackingEvent.Pause(timestampMillis = 15)

        var newState = useCase(currentState, pauseEvent)
        assertThat(newState).isInstanceOf(TrackingState.Paused::class.java)

        newState = newState as TrackingState.Paused
        assertThat(newState.metrics).isEqualTo(metrics)
    }

    @Test
    fun `resume from Paused transitions to Tracking and updates lastUpdateTimestampMillis`() {
        val pausedStateMetrics = sampleMetrics()
        val pausedState = TrackingState.Paused(pausedStateMetrics)

        val resumeEvent = TrackingEvent.Resume(20)
        var newState = useCase(pausedState, resumeEvent)
        assertThat(newState).isInstanceOf(TrackingState.Tracking::class.java)

        newState = newState as TrackingState.Tracking
        assertThat(newState.metrics.lastUpdateTimestampMillis).isEqualTo(resumeEvent.timestampMillis) // must be 20 as defined above
        assertThat(newState.metrics.path).isEqualTo(pausedStateMetrics.path)
        assertThat(newState.metrics.elapsedMillis).isEqualTo(pausedStateMetrics.elapsedMillis)
        assertThat(newState.metrics.distanceMeters).isEqualTo(pausedState.metrics.distanceMeters)
    }

    @Test
    fun `pause is ignored when current state is Idle`() {
        val idleState = TrackingState.Idle

        val newState = useCase(idleState, TrackingEvent.Pause(10))
        assertThat(newState).isEqualTo(TrackingState.Idle)
    }

    @Test
    fun `locationReceived is ignored when current state is Paused`() {
        val pausedMetrics = sampleMetrics()
        val currentState = TrackingState.Paused(pausedMetrics)
        val locationReceivedEvent = TrackingEvent.LocationReceived(point2, 15)

        val newState = useCase(currentState, locationReceivedEvent)

        assertThat(newState).isInstanceOf(TrackingState.Paused::class.java)
        assertThat((newState as TrackingState.Paused).metrics).isEqualTo(pausedMetrics)
    }

    @Test
    fun `locationReceived from Tracking updates distance, elapsed time and path`() {
        val currentState = TrackingState.Tracking(sampleMetrics())
        val newUpdateEvent = TrackingEvent.LocationReceived(point2, 20)
        val distanceMeters = currentState.metrics.path.last().distanceTo(newUpdateEvent.coordinates)
        val deltaTime =
            newUpdateEvent.timestampMillis - currentState.metrics.lastUpdateTimestampMillis

        var newState = useCase(currentState, newUpdateEvent)
        assertThat(newState).isInstanceOf(TrackingState.Tracking::class.java)

        newState = newState as TrackingState.Tracking
        assertThat(newState.metrics.distanceMeters).isEqualTo(currentState.metrics.distanceMeters + distanceMeters)
        assertThat(newState.metrics.elapsedMillis).isEqualTo(currentState.metrics.elapsedMillis + deltaTime)
        assertThat(newState.metrics.path).hasSize(2)
        assertThat(newState.metrics.path).containsExactly(point1, point2)
        assertThat(newState.metrics.lastUpdateTimestampMillis).isEqualTo(newUpdateEvent.timestampMillis)
    }

    @Test
    fun `stop from Tracking transitions to Finished`() {
        val currentState = TrackingState.Tracking(sampleMetrics())
        val stopEvent = TrackingEvent.Stop(currentState.metrics.lastUpdateTimestampMillis + 10)

        val newState = useCase(currentState, stopEvent)

        assertThat(newState).isInstanceOf(TrackingState.Finished::class.java)
        assertThat((newState as TrackingState.Finished).metrics).isEqualTo(currentState.metrics)
    }

    @Test
    fun `stop from Paused transitions to Finished`() {
        val currentState = TrackingState.Paused(sampleMetrics())
        val stopEvent = TrackingEvent.Stop(currentState.metrics.lastUpdateTimestampMillis + 10)

        val newState = useCase(currentState, stopEvent)

        assertThat(newState).isInstanceOf(TrackingState.Finished::class.java)
        assertThat((newState as TrackingState.Finished).metrics).isEqualTo(currentState.metrics)
    }

    @Test
    fun `start is ignored when current state is Tracking`() {
        val trackingState = TrackingState.Tracking(sampleMetrics())
        val startEvent = TrackingEvent.Start(point2, 30)

        val newState = useCase(trackingState, startEvent)

        assertThat(newState).isEqualTo(trackingState)
    }

    @Test
    fun `locationReceived is ignored when current state is Idle`() {
        val idleState = TrackingState.Idle
        val locationReceivedEvent = TrackingEvent.LocationReceived(point1, 10)

        val newState = useCase(idleState, locationReceivedEvent)

        assertThat(newState).isEqualTo(idleState)
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