package dev.roozbahani.trailmetrics.feature.route

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
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

    private companion object {
        val START = Coordinates(latitude = 52.52, longitude = 13.405)
    }
}
