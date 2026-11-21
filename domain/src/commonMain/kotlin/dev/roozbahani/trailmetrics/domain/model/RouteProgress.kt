package dev.roozbahani.trailmetrics.domain.model

import dev.roozbahani.trailmetrics.domain.util.distanceTo

data class RouteProgress(
    val traveledSegment: List<Coordinates>,
    val remainingSegment: List<Coordinates>,
    val lastIndex: Int
)

/**
 * Splits [plannedRoute] at the point closest to [currentLocation], searching from [previousIndex]
 * up to [searchWindow] points ahead.
 *
 * Out-of-range input is clamped, never thrown on: [previousIndex] is clamped to
 * `0..plannedRoute.lastIndex` (so an index at or past the size means the last point, a negative one
 * the first), and a negative [searchWindow] counts as 0. An empty route returns empty segments
 * and index 0.
 */
fun calculateRouteProgress(
    plannedRoute: List<Coordinates>,
    currentLocation: Coordinates,
    previousIndex: Int = 0,
    searchWindow: Int = 10
): RouteProgress {
    if (plannedRoute.isEmpty()) return RouteProgress(emptyList(), emptyList(), 0)

    val startIndex = previousIndex.coerceIn(0, plannedRoute.lastIndex)
    val windowEnd = (startIndex.toLong() + searchWindow.coerceAtLeast(0))
        .coerceAtMost(plannedRoute.lastIndex.toLong()).toInt()
    val searchRange = startIndex..windowEnd

    val closestIndex = searchRange.minByOrNull { index ->
        plannedRoute[index].distanceTo(currentLocation)
    } ?: startIndex

    return RouteProgress(
        traveledSegment = plannedRoute.subList(0, closestIndex + 1),
        remainingSegment = plannedRoute.subList(closestIndex, plannedRoute.size),
        lastIndex = closestIndex
    )
}
