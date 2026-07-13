package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteDraft
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository

class GenerateClosedRouteUseCase(
    private val directionsRepository: DirectionsRepository
) {
    suspend operator fun invoke(draft: RouteDraft): Result<Route> {
        if (draft.waypoints.size < MIN_WAYPOINTS) {
            return Result.failure(
                RouteError.InsufficientWaypoints(
                    required = MIN_WAYPOINTS,
                    actual = draft.waypoints.size
                )
            )
        }

        return directionsRepository.getClosedRoute(
            startPoint = draft.startPoint.coordinates,
            waypoints = draft.waypoints.map { it.coordinates }
        )
    }

    private companion object {
        const val MIN_WAYPOINTS = 3
    }
}
