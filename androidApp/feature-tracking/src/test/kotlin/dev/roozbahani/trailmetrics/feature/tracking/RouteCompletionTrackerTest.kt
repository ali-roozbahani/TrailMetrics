package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.distanceTo
import dev.roozbahani.trailmetrics.feature.tracking.RouteCompletionTracker.Companion.ROUTE_COMPLETION_INDEX_MARGIN
import dev.roozbahani.trailmetrics.feature.tracking.RouteCompletionTracker.Companion.ROUTE_COMPLETION_THRESHOLD_METERS
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RouteCompletionTrackerTest {

    private val tracker = RouteCompletionTracker(ROUTE)

    private fun metricsAt(location: Coordinates) = TrackingMetrics(
        elapsedMillis = 60_000L,
        lastUpdateTimestampMillis = 60_000L,
        distanceMeters = 500.0,
        path = listOf(location)
    )

    private fun RouteCompletionTracker.trackingAt(location: Coordinates): Boolean =
        onUpdate(location, TrackingState.Tracking(metricsAt(location)))

    @Test
    fun `the rule keeps its current thresholds`() {
        assertEquals(25.0, ROUTE_COMPLETION_THRESHOLD_METERS)
        assertEquals(3, ROUTE_COMPLETION_INDEX_MARGIN)
    }

    // region progress

    @Test
    fun `there is no progress and no stop before the first location`() {
        assertFalse(tracker.onUpdate(null, TrackingState.Idle))

        assertNull(tracker.progress)
        assertFalse(tracker.hasReachedDestination)
    }

    @Test
    fun `progress follows the current location along the planned route`() {
        assertFalse(tracker.trackingAt(ROUTE[2]))

        val progress = assertNotNull(tracker.progress)
        assertEquals(2, progress.lastIndex)
        assertEquals(ROUTE.subList(0, 3), progress.traveledSegment)
        assertEquals(ROUTE.subList(2, ROUTE.size), progress.remainingSegment)
    }

    @Test
    fun `progress never moves backwards along the route`() {
        tracker.trackingAt(ROUTE[3])

        tracker.trackingAt(ROUTE[0])

        assertEquals(3, assertNotNull(tracker.progress).lastIndex)
    }

    @Test
    fun `progress is kept when the location goes away`() {
        tracker.trackingAt(ROUTE[2])
        val progress = tracker.progress

        assertFalse(tracker.onUpdate(null, TrackingState.Finished(metricsAt(ROUTE[2]))))

        assertEquals(progress, tracker.progress)
    }

    // endregion

    // region completion

    @Test
    fun `reaching the end of the route while tracking stops exactly once`() {
        assertTrue(tracker.trackingAt(ROUTE.last()))
        assertTrue(tracker.hasReachedDestination)

        assertFalse(tracker.trackingAt(ROUTE.last()))
        assertFalse(tracker.trackingAt(BEYOND_END_WITHIN_THRESHOLD))
        assertTrue(tracker.hasReachedDestination)
    }

    @Test
    fun `the third-to-last point counts as the end when it is within the threshold`() {
        assertTrue(ROUTE[ROUTE.size - 3].distanceTo(ROUTE.last()) <= ROUTE_COMPLETION_THRESHOLD_METERS)

        assertTrue(tracker.trackingAt(ROUTE[ROUTE.size - 3]))
    }

    @Test
    fun `a point before the last three does not count as the end even within the threshold`() {
        assertTrue(ROUTE[ROUTE.size - 4].distanceTo(ROUTE.last()) <= ROUTE_COMPLETION_THRESHOLD_METERS)

        assertFalse(tracker.trackingAt(ROUTE[ROUTE.size - 4]))
        assertFalse(tracker.hasReachedDestination)
    }

    @Test
    fun `a location past the end within the threshold stops`() {
        assertTrue(tracker.trackingAt(BEYOND_END_WITHIN_THRESHOLD))
    }

    @Test
    fun `a location past the end outside the threshold does not stop`() {
        assertFalse(tracker.trackingAt(BEYOND_END_OUTSIDE_THRESHOLD))

        assertEquals(ROUTE.lastIndex, assertNotNull(tracker.progress).lastIndex)
        assertFalse(tracker.hasReachedDestination)
    }

    @Test
    fun `the start of a closed loop does not count as its end`() {
        val loopTracker = RouteCompletionTracker(LOOP)

        assertFalse(loopTracker.trackingAt(LOOP.first()))
        assertEquals(0, assertNotNull(loopTracker.progress).lastIndex)
    }

    @Test
    fun `being paused at the end does not stop until tracking resumes`() {
        assertFalse(tracker.onUpdate(ROUTE.last(), TrackingState.Paused(metricsAt(ROUTE.last()))))
        assertFalse(tracker.hasReachedDestination)

        assertTrue(tracker.trackingAt(ROUTE.last()))
    }

    @Test
    fun `an empty planned route never completes`() {
        val emptyRouteTracker = RouteCompletionTracker(emptyList())

        assertFalse(emptyRouteTracker.trackingAt(ROUTE.last()))
        assertFalse(emptyRouteTracker.hasReachedDestination)
    }

    // endregion

    private companion object {
        /**
         * Five points ~111 m apart, then three points ~5.6 m apart, so the last four points are all
         * within the 25 m threshold of the end and only the index margin tells them apart.
         */
        val ROUTE = listOf(0.0, 0.001, 0.002, 0.003, 0.00400, 0.00405, 0.00410, 0.00415)
            .map { Coordinates(latitude = 52.0 + it, longitude = 13.0) }

        /** ~22 m and ~27 m past the last point, on the same line. */
        val BEYOND_END_WITHIN_THRESHOLD = Coordinates(latitude = 52.00435, longitude = 13.0)
        val BEYOND_END_OUTSIDE_THRESHOLD = Coordinates(latitude = 52.00439, longitude = 13.0)

        /** A closed loop: starts and ends at the same point, as generated routes do. */
        val LOOP = listOf(
            Coordinates(latitude = 52.000, longitude = 13.000),
            Coordinates(latitude = 52.001, longitude = 13.000),
            Coordinates(latitude = 52.001, longitude = 13.001),
            Coordinates(latitude = 52.000, longitude = 13.001),
            Coordinates(latitude = 52.000, longitude = 13.000)
        )
    }
}
