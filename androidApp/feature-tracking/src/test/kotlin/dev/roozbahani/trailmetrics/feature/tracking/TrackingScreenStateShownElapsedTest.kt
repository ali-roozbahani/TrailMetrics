package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import org.junit.Test
import kotlin.test.assertEquals

/**
 * The time the Time cell shows from the screen state and the latest tick, which come from two collectors: at a state
 * change one can arrive before the other, and the cell must not show the tick of the state before.
 */
class TrackingScreenStateShownElapsedTest {

    private val metrics = TrackingMetrics(
        elapsedMillis = 12_000L,
        lastUpdateElapsedRealtimeMillis = 20_000L,
        distanceMeters = 40.0,
        path = listOf(Coordinates(latitude = 52.0, longitude = 13.0))
    )

    @Test
    fun `while tracking the cell shows the tick`() {
        assertEquals(13_000L, TrackingScreenState(TrackingState.Tracking(metrics)).shownElapsedMillis(tick = 13_000L))
    }

    @Test
    fun `while tracking a tick older than a new fix does not take the cell back`() {
        assertEquals(12_000L, TrackingScreenState(TrackingState.Tracking(metrics)).shownElapsedMillis(tick = 11_000L))
    }

    @Test
    fun `a Pause that arrives before its tick shows the paused time, not the tick of the running session`() {
        assertEquals(12_000L, TrackingScreenState(TrackingState.Paused(metrics)).shownElapsedMillis(tick = 12_900L))
    }

    @Test
    fun `a Stop that arrives before its tick shows the final time`() {
        assertEquals(12_000L, TrackingScreenState(TrackingState.Finished(metrics)).shownElapsedMillis(tick = 12_900L))
    }

    @Test
    fun `idle shows no time whatever the last tick was`() {
        assertEquals(0L, TrackingScreenState(TrackingState.Idle).shownElapsedMillis(tick = 12_900L))
    }
}
