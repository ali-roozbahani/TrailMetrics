package dev.roozbahani.trailmetrics.feature.route

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RouteStateTest {

    private fun waypoints(count: Int) = List(count) { index ->
        RoutePoint(Coordinates(latitude = 52.0 + index * 0.001, longitude = 13.0), order = index)
    }

    @Test
    fun `defaults are empty, not loading and Running`() {
        val state = RouteState()

        assertNull(state.startPoint)
        assertEquals(emptyList(), state.waypoints)
        assertNull(state.generatedRoute)
        assertNull(state.userProfile)
        assertEquals(ActivityType.Running, state.selectedActivityType)
        assertFalse(state.isLoading)
        assertFalse(state.canGenerateRoute)
    }

    @Test
    fun `canGenerateRoute is true from three waypoints with a start point`() {
        assertFalse(RouteState(startPoint = START, waypoints = waypoints(2)).canGenerateRoute, "two waypoints")
        assertTrue(RouteState(startPoint = START, waypoints = waypoints(3)).canGenerateRoute, "three waypoints")
        assertTrue(RouteState(startPoint = START, waypoints = waypoints(4)).canGenerateRoute, "four waypoints")
    }

    @Test
    fun `canGenerateRoute is false without a start point for any waypoint count`() {
        listOf(2, 3, 4).forEach { count ->
            val state = RouteState(startPoint = null, waypoints = waypoints(count))

            assertFalse(state.canGenerateRoute, "$count waypoints")
        }
    }

    @Test
    fun `canGenerateRoute is false while loading even when everything else holds`() {
        val state = RouteState(startPoint = START, waypoints = waypoints(4), isLoading = true)

        assertFalse(state.canGenerateRoute)
    }

    @Test
    fun `planPoints are the start point then the waypoints then the route points`() {
        val route = Route(points = listOf(RoutePoint(START, 0), RoutePoint(OTHER, 1)), distanceMeters = 10.0)
        val state = RouteState(startPoint = START, waypoints = waypoints(2), generatedRoute = route)

        assertEquals(listOf(START) + waypoints(2).map { it.coordinates } + listOf(START, OTHER), state.planPoints)
        assertEquals(emptyList(), RouteState().planPoints)
    }

    @Test
    fun `a new location keeps the start point only when something was planned from it`() {
        assertFalse(RouteState().hasPlannedFromStart, "nothing planned")
        assertFalse(RouteState(startPoint = START).hasPlannedFromStart, "only a start point")
        assertFalse(RouteState(waypoints = waypoints(2)).hasPlannedFromStart, "no start point")
        assertTrue(RouteState(startPoint = START, waypoints = waypoints(1)).hasPlannedFromStart, "a waypoint")
        val route = Route(points = emptyList(), distanceMeters = 0.0)
        assertTrue(RouteState(startPoint = START, generatedRoute = route).hasPlannedFromStart, "a route")
    }

    @Test
    fun `the camera fits a plan whose first waypoints arrive two or more at a time and only once`() {
        assertFalse(isPlanFitNeeded(emptyList(), planAlreadySeen = false), "no waypoints")
        assertFalse(isPlanFitNeeded(waypoints(1), planAlreadySeen = false), "a tapped first waypoint")
        assertTrue(isPlanFitNeeded(waypoints(2), planAlreadySeen = false), "a restored plan")
        assertTrue(isPlanFitNeeded(waypoints(5), planAlreadySeen = false), "a restored plan")
        assertFalse(isPlanFitNeeded(waypoints(5), planAlreadySeen = true), "after the first waypoints")
    }

    private companion object {
        val OTHER = Coordinates(latitude = 48.137, longitude = 11.575)
        val START = Coordinates(latitude = 52.52, longitude = 13.405)
    }
}
