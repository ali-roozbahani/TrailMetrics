package dev.roozbahani.trailmetrics.domain.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class RouteProgressTest {

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.337, 12.389)
    private val point3 = Coordinates(51.338, 12.390)
    private val plannedRoute = listOf(point1, point2, point3)

    @Test
    fun `empty planned route returns empty segments`() {
        val result = calculateRouteProgress(plannedRoute = emptyList(), currentLocation = point1)
        assertThat(result.traveledSegment).hasSize(0)
        assertThat(result.remainingSegment).hasSize(0)
    }

    @Test
    fun `user at first point has minimal traveled segment`() {
        val currentLocation = point1

        val result = calculateRouteProgress(plannedRoute, currentLocation)

        assertThat(result.traveledSegment).containsExactly(point1)
        assertThat(result.remainingSegment).containsExactly(point1, point2, point3)
    }

    @Test
    fun `user at last point has full traveled segment`() {
        val currentLocation = point3

        val result = calculateRouteProgress(plannedRoute, currentLocation)

        assertThat(result.traveledSegment).containsExactly(point1, point2, point3)
        assertThat(result.remainingSegment).containsExactly(point3)
    }

    @Test
    fun `user at middle point splits route correctly`() {
        val currentLocation = point2

        val result = calculateRouteProgress(plannedRoute, currentLocation)

        assertThat(result.traveledSegment).containsExactly(point1, point2)
        assertThat(result.remainingSegment).containsExactly(point2, point3)
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

        // بدون previousIndex (رفتار قدیمی) - انتظار داریم اشتباه بره سراغ index 3
        val resultWithoutFix = calculateRouteProgress(loopRoute, currentLocation)
        assertThat(resultWithoutFix.lastIndex).isEqualTo(3)  // این باگ قدیمی رو مستند می‌کنه

// با previousIndex=1 (رفتار جدید) - باید نزدیک 1/2 بمونه، نه بپره به 3
        val resultWithFix = calculateRouteProgress(loopRoute, currentLocation, previousIndex = 1, searchWindow = 1)
        assertThat(resultWithFix.lastIndex).isAtMost(2)
    }
}
