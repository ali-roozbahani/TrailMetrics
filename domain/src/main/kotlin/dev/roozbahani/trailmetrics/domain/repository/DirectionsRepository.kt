package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route

interface DirectionsRepository {
    suspend fun getClosedRoute(
        startPoint: Coordinates,
        waypoints: List<Coordinates>
    ): Result<Route>
}
