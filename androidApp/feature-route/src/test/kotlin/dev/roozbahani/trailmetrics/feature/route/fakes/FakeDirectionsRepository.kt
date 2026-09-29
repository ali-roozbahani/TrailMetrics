package dev.roozbahani.trailmetrics.feature.route.fakes

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import kotlinx.coroutines.CompletableDeferred

class FakeDirectionsRepository(
    var closedRouteResult: Result<Route>
) : DirectionsRepository {
    /** When set, getClosedRoute suspends until it is completed, so in-flight state can be observed. */
    var gate: CompletableDeferred<Unit>? = null

    val requests = mutableListOf<Pair<Coordinates, List<Coordinates>>>()

    override suspend fun getClosedRoute(
        startPoint: Coordinates,
        waypoints: List<Coordinates>
    ): Result<Route> {
        requests += startPoint to waypoints
        gate?.await()
        return closedRouteResult
    }
}
