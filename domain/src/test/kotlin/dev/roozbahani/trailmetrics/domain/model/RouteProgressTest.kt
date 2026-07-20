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
}
