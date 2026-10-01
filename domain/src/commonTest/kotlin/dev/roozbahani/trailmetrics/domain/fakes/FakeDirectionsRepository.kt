package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository

class FakeDirectionsRepository : DirectionsRepository {
    var closedRouteResult: Result<Route> =
        Result.failure(IllegalStateException("FakeDirectionsRepository: closedRouteResult not set"))
    val closedRouteRequests = mutableListOf<Pair<Coordinates, List<Coordinates>>>()

    override suspend fun getClosedRoute(startPoint: Coordinates, waypoints: List<Coordinates>): Result<Route> {
        closedRouteRequests += startPoint to waypoints
        return closedRouteResult
    }
}
