package dev.roozbahani.trailmetrics.domain.model

import dev.roozbahani.trailmetrics.domain.util.distanceTo

data class RouteProgress(
    val traveledSegment: List<Coordinates>,
    val remainingSegment: List<Coordinates>,
    val lastIndex: Int
)

fun calculateRouteProgress(
    plannedRoute: List<Coordinates>,
    currentLocation: Coordinates,
    previousIndex: Int = 0,
    searchWindow: Int = 10   // فقط تا ۱۰ نقطه جلوتر از موقعیت قبلی رو بگرد
): RouteProgress {
    if (plannedRoute.isEmpty()) return RouteProgress(emptyList(), emptyList(), 0)

    val windowEnd = (previousIndex + searchWindow).coerceAtMost(plannedRoute.size - 1)
    val searchRange = previousIndex..windowEnd

    val closestIndex = searchRange.minByOrNull { index ->
        plannedRoute[index].distanceTo(currentLocation)
    } ?: previousIndex

    return RouteProgress(
        traveledSegment = plannedRoute.subList(0, closestIndex + 1),
        remainingSegment = plannedRoute.subList(closestIndex, plannedRoute.size),
        lastIndex = closestIndex
    )
}
