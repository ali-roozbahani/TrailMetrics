package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.fakes.FakeDirectionsRepository
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteDraft
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlin.test.assertTrue

class GenerateClosedRouteUseCaseTest {

    private val directionsRepository = FakeDirectionsRepository()
    private val useCase = GenerateClosedRouteUseCase(directionsRepository)

    private val start = RoutePoint(Coordinates(51.336, 12.388), order = 0)
    private val waypoint1 = RoutePoint(Coordinates(51.327, 12.394), order = 1)
    private val waypoint2 = RoutePoint(Coordinates(51.320, 12.380), order = 2)
    private val waypoint3 = RoutePoint(Coordinates(51.330, 12.370), order = 3)
    private val waypoint4 = RoutePoint(Coordinates(51.340, 12.375), order = 4)

    @Test
    fun `fewer than three waypoints throws InsufficientWaypoints without calling the repository`() = runTest {
        val tooFew = listOf(emptyList(), listOf(waypoint1), listOf(waypoint1, waypoint2))

        tooFew.forEach { waypoints ->
            val error = assertFailsWith<RouteError.InsufficientWaypoints> {
                useCase(RouteDraft(start, waypoints))
            }
            assertEquals(RouteError.InsufficientWaypoints(required = 3, actual = waypoints.size), error)
        }
        assertTrue(directionsRepository.closedRouteRequests.isEmpty())
    }

    @Test
    fun `three waypoints passes start and waypoint coordinates to the repository and returns its route`() = runTest {
        val route = Route(points = listOf(start, waypoint1, waypoint2, waypoint3, start), distanceMeters = 4200.0)
        directionsRepository.closedRouteResult = Result.success(route)

        val result = useCase(RouteDraft(start, listOf(waypoint1, waypoint2, waypoint3)))

        assertSame(route, result)
        assertEquals(
            listOf(start.coordinates to listOf(waypoint1.coordinates, waypoint2.coordinates, waypoint3.coordinates)),
            directionsRepository.closedRouteRequests
        )
    }

    @Test
    fun `more than three waypoints are all passed to the repository in draft order`() = runTest {
        directionsRepository.closedRouteResult = Result.success(Route(points = emptyList(), distanceMeters = 0.0))

        useCase(RouteDraft(start, listOf(waypoint4, waypoint1, waypoint3, waypoint2)))

        assertEquals(
            listOf(
                start.coordinates to listOf(
                    waypoint4.coordinates,
                    waypoint1.coordinates,
                    waypoint3.coordinates,
                    waypoint2.coordinates
                )
            ),
            directionsRepository.closedRouteRequests
        )
    }

    @Test
    fun `repository failure is rethrown`() = runTest {
        val failure = RouteError.DirectionsApiError(IllegalStateException("quota exceeded"))
        directionsRepository.closedRouteResult = Result.failure(failure)

        val thrown = assertFailsWith<RouteError.DirectionsApiError> {
            useCase(RouteDraft(start, listOf(waypoint1, waypoint2, waypoint3)))
        }

        assertSame(failure, thrown)
    }
}
