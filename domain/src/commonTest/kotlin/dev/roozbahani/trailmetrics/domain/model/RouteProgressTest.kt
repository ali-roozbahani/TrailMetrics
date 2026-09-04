package dev.roozbahani.trailmetrics.domain.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RouteProgressTest {

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.337, 12.389)
    private val point3 = Coordinates(51.338, 12.390)
    private val plannedRoute = listOf(point1, point2, point3)

    @Test
    fun `empty planned route returns empty segments`() {
        val result = calculateRouteProgress(plannedRoute = emptyList(), currentLocation = point1)
        assertEquals(0, result.traveledSegment.size)
        assertEquals(0, result.remainingSegment.size)
    }

    @Test
    fun `user at first point has minimal traveled segment`() {
        val currentLocation = point1

        val result = calculateRouteProgress(plannedRoute, currentLocation)

        val expectedTraveled = listOf(point1)
        assertTrue(result.traveledSegment.size == expectedTraveled.size && result.traveledSegment.containsAll(expectedTraveled))
        val expectedRemaining = listOf(point1, point2, point3)
        assertTrue(result.remainingSegment.size == expectedRemaining.size && result.remainingSegment.containsAll(expectedRemaining))
    }

    @Test
    fun `user at last point has full traveled segment`() {
        val currentLocation = point3

        val result = calculateRouteProgress(plannedRoute, currentLocation)

        val expectedTraveled = listOf(point1, point2, point3)
        assertTrue(result.traveledSegment.size == expectedTraveled.size && result.traveledSegment.containsAll(expectedTraveled))
        val expectedRemaining = listOf(point3)
        assertTrue(result.remainingSegment.size == expectedRemaining.size && result.remainingSegment.containsAll(expectedRemaining))
    }

    @Test
    fun `user at middle point splits route correctly`() {
        val currentLocation = point2

        val result = calculateRouteProgress(plannedRoute, currentLocation)

        val expectedTraveled = listOf(point1, point2)
        assertTrue(result.traveledSegment.size == expectedTraveled.size && result.traveledSegment.containsAll(expectedTraveled))
        val expectedRemaining = listOf(point2, point3)
        assertTrue(result.remainingSegment.size == expectedRemaining.size && result.remainingSegment.containsAll(expectedRemaining))
    }

    @Test
    fun `closed loop route does not jump backward in progress calculation`() {
        // Build a closed-loop route where a point near the end is geographically
        // close to a point near the beginning (because the loop closes back on itself)
        val loopRoute = listOf(
            Coordinates(51.336, 12.388),  // start (index 0)
            Coordinates(51.337, 12.390),  // index 1
            Coordinates(51.338, 12.392),  // index 2
            Coordinates(51.337, 12.389),  // index 3 - close to index 0/1 since the loop closes
            Coordinates(51.336, 12.388)   // end (index 4) - same as the start point
        )
        // The user is actually near index 1
        val currentLocation = Coordinates(51.3369, 12.3889)

        // Without previousIndex (old behavior) - expected to incorrectly jump to index 3
        val resultWithoutFix = calculateRouteProgress(loopRoute, currentLocation)
        assertEquals(3, resultWithoutFix.lastIndex)  // documents the old bug

        // With previousIndex=1 (new behavior) - should stay near 1/2, not jump to 3
        val resultWithFix = calculateRouteProgress(loopRoute, currentLocation, previousIndex = 1, searchWindow = 1)
        assertTrue(resultWithFix.lastIndex <= 2)
    }
}
