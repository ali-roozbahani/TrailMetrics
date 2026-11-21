package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteProgress
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.distanceTo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

class RouteCompletionTrackerTest {

    private val tracker = RouteCompletionTracker(ROUTE)

    private fun metricsAt(location: Coordinates) = TrackingMetrics(
        elapsedMillis = 60_000L,
        lastUpdateElapsedRealtimeMillis = 60_000L,
        distanceMeters = 500.0,
        path = listOf(location)
    )

    private fun RouteCompletionTracker.trackingAt(location: Coordinates): RouteCompletionUpdate =
        update(location, TrackingState.Tracking(metricsAt(location)))

    @Test
    fun `the rule keeps its current thresholds`() {
        // 25 m: stops at exactly 25.0 m and not beyond; 3 points: index size - 3 counts, size - 4 does not.
        val equatorTracker = RouteCompletionTracker(EQUATOR_ROUTE)
        assertEquals(25.0, AT_THRESHOLD.distanceTo(EQUATOR_ROUTE.last()))
        assertTrue(equatorTracker.trackingAt(AT_THRESHOLD).reachedNow)
        assertTrue(tracker.trackingAt(ROUTE[ROUTE.size - 3]).reachedNow)
        assertFalse(RouteCompletionTracker(ROUTE).trackingAt(ROUTE[ROUTE.size - 4]).reachedNow)
    }

    // region no planned route (a restored session)

    @Test
    fun `with an empty planned route a tracking fix neither completes nor crashes`() {
        val emptyTracker = RouteCompletionTracker(emptyList())

        val result = emptyTracker.update(ROUTE[0], TrackingState.Tracking(metricsAt(ROUTE[0])))

        assertFalse(result.reachedNow)
        assertEquals(RouteProgress(emptyList(), emptyList(), 0), result.progress)
    }

    @Test
    fun `with an empty planned route a Finished or Paused state with a path neither completes nor crashes`() {
        val emptyTracker = RouteCompletionTracker(emptyList())

        listOf(TrackingState.Finished(metricsAt(ROUTE[1])), TrackingState.Paused(metricsAt(ROUTE[1]))).forEach {
            assertFalse(emptyTracker.update(ROUTE[1], it).reachedNow)
        }
    }

    // endregion

    // region progress

    @Test
    fun `there is no stop while idle before the first location`() {
        assertFalse(tracker.update(ROUTE[0], TrackingState.Idle).reachedNow)
    }

    @Test
    fun `progress follows the current location along the planned route`() {
        val result = tracker.trackingAt(ROUTE[2])

        assertFalse(result.reachedNow)
        val progress = result.progress
        assertEquals(2, progress.lastIndex)
        assertEquals(ROUTE.subList(0, 3), progress.traveledSegment)
        assertEquals(ROUTE.subList(2, ROUTE.size), progress.remainingSegment)
    }

    @Test
    fun `progress never moves backwards along the route`() {
        tracker.trackingAt(ROUTE[3])

        val result = tracker.trackingAt(ROUTE[0])

        assertEquals(3, result.progress.lastIndex)
    }

    @Test
    fun `progress is kept when the location goes away`() {
        val progress = tracker.trackingAt(ROUTE[2]).progress

        val result = tracker.update(ROUTE[2], TrackingState.Finished(metricsAt(ROUTE[2])))

        assertFalse(result.reachedNow)
        assertEquals(progress, result.progress)
    }

    @Test
    fun `the same location twice does not recalculate progress`() {
        val progress = tracker.trackingAt(ROUTE[2]).progress

        assertSame(progress, tracker.trackingAt(ROUTE[2]).progress)
    }

    // endregion

    // region completion

    @Test
    fun `reaching the end of the route while tracking stops exactly once`() {
        assertTrue(tracker.trackingAt(ROUTE.last()).reachedNow)

        assertFalse(tracker.trackingAt(ROUTE.last()).reachedNow)
        assertFalse(tracker.trackingAt(BEYOND_END_WITHIN_THRESHOLD).reachedNow)
    }

    @Test
    fun `the third-to-last point counts as the end when it is within the threshold`() {
        assertTrue(ROUTE[ROUTE.size - 3].distanceTo(ROUTE.last()) <= 25.0)

        assertTrue(tracker.trackingAt(ROUTE[ROUTE.size - 3]).reachedNow)
    }

    @Test
    fun `a point before the last three does not count as the end even within the threshold`() {
        assertTrue(ROUTE[ROUTE.size - 4].distanceTo(ROUTE.last()) <= 25.0)

        assertFalse(tracker.trackingAt(ROUTE[ROUTE.size - 4]).reachedNow)
    }

    @Test
    fun `a location past the end within the threshold stops`() {
        assertTrue(tracker.trackingAt(BEYOND_END_WITHIN_THRESHOLD).reachedNow)
    }

    @Test
    fun `a location past the end outside the threshold does not stop`() {
        val result = tracker.trackingAt(BEYOND_END_OUTSIDE_THRESHOLD)

        assertFalse(result.reachedNow)
        assertEquals(ROUTE.lastIndex, result.progress.lastIndex)
    }

    @Test
    fun `the start of a closed loop does not count as its end`() {
        val loopTracker = RouteCompletionTracker(LOOP)

        val result = loopTracker.trackingAt(LOOP.first())

        assertFalse(result.reachedNow)
        assertEquals(0, result.progress.lastIndex)
    }

    @Test
    fun `being paused at the end does not stop until tracking resumes`() {
        assertFalse(tracker.update(ROUTE.last(), TrackingState.Paused(metricsAt(ROUTE.last()))).reachedNow)

        assertTrue(tracker.trackingAt(ROUTE.last()).reachedNow)
    }

    @Test
    fun `being at the end while idle or finished does not stop`() {
        assertFalse(tracker.update(ROUTE.last(), TrackingState.Idle).reachedNow)
        val finished = TrackingState.Finished(metricsAt(ROUTE.last()))
        assertFalse(tracker.update(BEYOND_END_WITHIN_THRESHOLD, finished).reachedNow)
    }

    @Test
    fun `a location exactly at the threshold distance from the end stops`() {
        val equatorTracker = RouteCompletionTracker(EQUATOR_ROUTE)
        assertEquals(25.0, AT_THRESHOLD.distanceTo(EQUATOR_ROUTE.last()))

        assertTrue(equatorTracker.trackingAt(AT_THRESHOLD).reachedNow)
    }

    @Test
    fun `a location just beyond the threshold distance from the end does not stop`() {
        val equatorTracker = RouteCompletionTracker(EQUATOR_ROUTE)
        assertTrue(JUST_BEYOND_THRESHOLD.distanceTo(EQUATOR_ROUTE.last()) > 25.0)

        val result = equatorTracker.trackingAt(JUST_BEYOND_THRESHOLD)

        assertFalse(result.reachedNow)
        assertEquals(EQUATOR_ROUTE.lastIndex, result.progress.lastIndex)
    }

    @Test
    fun `an empty planned route never completes`() {
        val emptyRouteTracker = RouteCompletionTracker(emptyList())

        assertFalse(emptyRouteTracker.trackingAt(ROUTE.last()).reachedNow)
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

        /**
         * Ends at (0, 0). Near zero a latitude step is far finer than a metre's rounding, so a point
         * exactly 25 m from the end exists; at 52° N none does.
         */
        val EQUATOR_ROUTE = listOf(-0.002, -0.001, 0.0).map { Coordinates(latitude = it, longitude = 0.0) }

        /** 25.0 m north of the end of [EQUATOR_ROUTE], and the next Double north of it (~25.000000000000007 m). */
        val AT_THRESHOLD = Coordinates(latitude = 0.00022483040147968267, longitude = 0.0)
        val JUST_BEYOND_THRESHOLD = Coordinates(latitude = 0.0002248304014796827, longitude = 0.0)

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
