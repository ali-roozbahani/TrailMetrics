package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteProgress
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.calculateRouteProgress
import dev.roozbahani.trailmetrics.domain.util.distanceTo

/** The result of [RouteCompletionTracker.update]: [progress] after the fix, and [reachedNow] true exactly once. */
data class RouteCompletionUpdate(val progress: RouteProgress, val reachedNow: Boolean)

/**
 * Progress along [plannedRoute], and the once-only decision that the route's end is reached.
 *
 * Progress is recalculated only when the location changes, and each calculation starts its search from
 * the previous progress index, so progress never moves backwards. The route counts as completed while
 * [TrackingState.Tracking], with a non-empty plan, once the progress index is within the last three points
 * and the location is within 25 m of the last point; a session without a plan never completes.
 *
 * Stateful and not thread-safe: use it from one coroutine only.
 */
class RouteCompletionTracker(private val plannedRoute: List<Coordinates>) {

    private var lastProgressIndex = 0
    private var lastLocation: Coordinates? = null
    private var progress = calculateRouteProgress(emptyList(), Coordinates(0.0, 0.0))
    private var hasReachedDestination = false

    fun update(location: Coordinates, state: TrackingState): RouteCompletionUpdate {
        if (location != lastLocation) {
            lastLocation = location
            val result = calculateRouteProgress(plannedRoute, location, lastProgressIndex)
            lastProgressIndex = result.lastIndex
            progress = result
        }

        val isRouteCompleted = plannedRoute.isNotEmpty() &&
            state is TrackingState.Tracking &&
            progress.lastIndex >= plannedRoute.size - ROUTE_COMPLETION_INDEX_MARGIN &&
            location.distanceTo(plannedRoute.last()) <= ROUTE_COMPLETION_THRESHOLD_METERS

        val reachedNow = isRouteCompleted && !hasReachedDestination
        if (reachedNow) hasReachedDestination = true
        return RouteCompletionUpdate(progress, reachedNow)
    }

    private companion object {
        const val ROUTE_COMPLETION_THRESHOLD_METERS = 25.0
        const val ROUTE_COMPLETION_INDEX_MARGIN = 3
    }
}
