package dev.roozbahani.trailmetrics.domain.model

import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import kotlin.test.Test
import kotlin.test.assertEquals

/** [displayedElapsedMillis] for every [TrackingState], the clamp, and its agreement with the accounting. */
class DisplayedElapsedTimeTest {

    private val point = Coordinates(51.0, 12.0)
    private val metrics = TrackingMetrics(
        elapsedMillis = 60_000L,
        lastUpdateElapsedRealtimeMillis = 100_000L,
        distanceMeters = 100.0,
        path = listOf(point)
    )
    private val updateTrackingState = UpdateTrackingStateUseCase()

    @Test
    fun `idle shows zero`() {
        assertEquals(0L, TrackingState.Idle.displayedElapsedMillis(nowElapsedRealtimeMillis = 500_000L))
    }

    @Test
    fun `tracking adds the time since the last accounted update`() {
        val shown = TrackingState.Tracking(metrics).displayedElapsedMillis(nowElapsedRealtimeMillis = 103_500L)

        assertEquals(63_500L, shown)
    }

    @Test
    fun `tracking at the last update shows the accounted time`() {
        assertEquals(60_000L, TrackingState.Tracking(metrics).displayedElapsedMillis(100_000L))
    }

    @Test
    fun `tracking clamps a now before the last update to the accounted time`() {
        assertEquals(60_000L, TrackingState.Tracking(metrics).displayedElapsedMillis(90_000L))
    }

    @Test
    fun `paused shows the accounted time however late now is`() {
        assertEquals(60_000L, TrackingState.Paused(metrics).displayedElapsedMillis(900_000L))
    }

    @Test
    fun `finished shows the accounted time however late now is`() {
        assertEquals(60_000L, TrackingState.Finished(metrics).displayedElapsedMillis(900_000L))
    }

    @Test
    fun `resume does not count the time spent paused`() {
        val paused = TrackingState.Paused(metrics)
        // Paused at 100 s of the monotonic clock, resumed at 400 s: 300 s of pause.
        val resumed = updateTrackingState(paused, TrackingEvent.Resume(elapsedRealtimeMillis = 400_000L))

        assertEquals(60_000L, resumed.displayedElapsedMillis(nowElapsedRealtimeMillis = 400_000L))
        assertEquals(62_000L, resumed.displayedElapsedMillis(nowElapsedRealtimeMillis = 402_000L))
    }

    @Test
    fun `the next location event accounts what was shown just before it`() {
        val tracking = TrackingState.Tracking(metrics)
        val shownBefore = tracking.displayedElapsedMillis(nowElapsedRealtimeMillis = 107_000L)

        val afterLocation = updateTrackingState(
            tracking,
            TrackingEvent.LocationReceived(point, elapsedRealtimeMillis = 107_000L, speedMetersPerSecond = null)
        )

        assertEquals(shownBefore, afterLocation.displayedElapsedMillis(nowElapsedRealtimeMillis = 107_000L))
        assertEquals(67_000L, (afterLocation as TrackingState.Tracking).metrics.elapsedMillis)
    }
}
