package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Runs each call of [delegate] on [Dispatchers.Default]. Ktor's HttpTimeout starts its timers in the caller's
 * context: under runTest's virtual time they would fire at once and every call would time out. The app calls
 * the repository from a real dispatcher, so this only puts the test back on real time.
 */
class RealTimeDirectionsRepository(private val delegate: DirectionsRepository) : DirectionsRepository {
    override suspend fun getClosedRoute(startPoint: Coordinates, waypoints: List<Coordinates>): Result<Route> =
        withContext(Dispatchers.Default) { delegate.getClosedRoute(startPoint, waypoints) }
}
