package dev.roozbahani.trailmetrics.domain.model

import dev.roozbahani.trailmetrics.domain.util.distanceTo

data class RouteProgress(
    val traveledSegment: List<Coordinates>,
    val remainingSegment: List<Coordinates>
)

fun calculateRouteProgress(
    plannedRoute: List<Coordinates>,
    currentLocation: Coordinates
): RouteProgress {
    if (plannedRoute.isEmpty()) return RouteProgress(emptyList(), emptyList())

    val closestIndex = plannedRoute.indices.minByOrNull { index ->
        plannedRoute[index].distanceTo(currentLocation)
    } ?: 0

    return RouteProgress(
        traveledSegment = plannedRoute.subList(0, closestIndex + 1),
        remainingSegment = plannedRoute.subList(closestIndex, plannedRoute.size)
    )
}