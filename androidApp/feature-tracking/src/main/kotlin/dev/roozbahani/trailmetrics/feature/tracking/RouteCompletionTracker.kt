package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteProgress
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.calculateRouteProgress
import dev.roozbahani.trailmetrics.domain.util.distanceTo

/**
 * Progress along the planned route, and the once-only decision to stop tracking when the
 * route's end is reached.
 *
 * Progress is recalculated only when the current location changes, and each calculation
 * starts its search from the previous progress index, so progress never moves backwards.
 */
internal class RouteCompletionTracker(private val plannedRoutePoints: List<Coordinates>) {

    var progress: RouteProgress? = null
        private set

    var hasReachedDestination: Boolean = false
        private set

    private var lastProgressIndex = 0
    private var lastLocation: Coordinates? = null

    /** Returns true exactly once: the first time the route counts as completed. */
    fun onUpdate(currentLocation: Coordinates?, trackingState: TrackingState): Boolean {
        if (currentLocation != lastLocation) {
            lastLocation = currentLocation
            currentLocation?.let {
                val result = calculateRouteProgress(plannedRoutePoints, it, lastProgressIndex)
                lastProgressIndex = result.lastIndex
                progress = result
            }
        }

        val currentProgress = progress
        val isRouteCompleted = currentLocation != null &&
            plannedRoutePoints.isNotEmpty() &&
            trackingState is TrackingState.Tracking &&
            currentProgress != null &&
            currentProgress.lastIndex >= plannedRoutePoints.size - ROUTE_COMPLETION_INDEX_MARGIN &&
            currentLocation.distanceTo(plannedRoutePoints.last()) <= ROUTE_COMPLETION_THRESHOLD_METERS

        if (isRouteCompleted && !hasReachedDestination) {
            hasReachedDestination = true
            return true
        }
        return false
    }

    internal companion object {
        const val ROUTE_COMPLETION_THRESHOLD_METERS = 25.0
        const val ROUTE_COMPLETION_INDEX_MARGIN = 3
    }
}
