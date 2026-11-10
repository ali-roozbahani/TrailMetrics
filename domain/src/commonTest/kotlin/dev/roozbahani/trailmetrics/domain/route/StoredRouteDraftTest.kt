package dev.roozbahani.trailmetrics.domain.route

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StoredRouteDraftTest {

    private val waypoint = RoutePoint(Coordinates(51.337, 12.389), 0)
    private val route = Route(points = emptyList(), distanceMeters = 0.0)

    private fun draft(startPoint: Coordinates?, waypoints: List<RoutePoint> = emptyList(), route: Route? = null) =
        StoredRouteDraft(startPoint, waypoints, route, ActivityType.Running)

    @Test
    fun `empty means no start point and no waypoints`() {
        assertTrue(draft(null).isEmpty)
        assertTrue(draft(null, route = route).isEmpty, "a route without a start point or waypoints")
        assertFalse(draft(STORED).isEmpty)
        assertFalse(draft(null, listOf(waypoint)).isEmpty)
    }

    @Test
    fun `planned from the start point needs a start point and waypoints or a route`() {
        assertFalse(draft(null).isPlannedFromStart, "nothing planned")
        assertFalse(draft(STORED).isPlannedFromStart, "only a start point")
        assertFalse(draft(null, listOf(waypoint)).isPlannedFromStart, "no start point")
        assertTrue(draft(STORED, listOf(waypoint)).isPlannedFromStart, "a waypoint")
        assertTrue(draft(STORED, route = route).isPlannedFromStart, "a route")
    }

    @Test
    fun `a restored plan keeps its start point only when something was planned from it`() {
        assertEquals(STORED, draft(STORED, listOf(waypoint)).startPointToShow(CURRENT))
        assertEquals(CURRENT, draft(STORED).startPointToShow(CURRENT), "a start point only")
        assertEquals(STORED, draft(STORED).startPointToShow(null), "no location known yet")
        assertEquals(CURRENT, draft(null, listOf(waypoint)).startPointToShow(CURRENT), "no stored start point")
        assertNull(draft(null, listOf(waypoint)).startPointToShow(null))
    }

    private companion object {
        val STORED = Coordinates(48.137, 11.575)
        val CURRENT = Coordinates(52.52, 13.405)
    }
}
