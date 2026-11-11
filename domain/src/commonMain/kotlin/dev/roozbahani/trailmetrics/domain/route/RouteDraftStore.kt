package dev.roozbahani.trailmetrics.domain.route

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import kotlin.coroutines.cancellation.CancellationException

/**
 * Keeps the one route being planned across process death, so the start point, the waypoints, the
 * generated route and the activity type survive until the plan is reset or used to start tracking.
 */
interface RouteDraftStore {
    /** Stores [draft], replacing the stored one. An empty draft ([StoredRouteDraft.isEmpty]) clears the store. */
    @Throws(Exception::class, CancellationException::class)
    suspend fun save(draft: StoredRouteDraft)

    /** The stored draft, or null. A stored draft is never empty. */
    @Throws(Exception::class, CancellationException::class)
    suspend fun load(): StoredRouteDraft?

    @Throws(Exception::class, CancellationException::class)
    suspend fun clear()
}

/**
 * A route plan as stored. Not [dev.roozbahani.trailmetrics.domain.model.RouteDraft], the input of route
 * generation, which has no generated route and no activity type and always has a start point.
 * [waypoints] and the points of [generatedRoute] are in order, each `order` equal to its index.
 */
data class StoredRouteDraft(
    val startPoint: Coordinates?,
    val waypoints: List<RoutePoint>,
    val generatedRoute: Route?,
    val activityType: ActivityType
) {
    /** No start point and no waypoints: nothing worth keeping. */
    val isEmpty: Boolean
        get() = startPoint == null && waypoints.isEmpty()

    /** Waypoints or a route were planned from [startPoint], so a new current location does not replace it. */
    val isPlannedFromStart: Boolean
        get() = startPoint != null && (waypoints.isNotEmpty() || generatedRoute != null)

    /**
     * The start point a restored plan shows when the screen already knows [currentLocation]: the plan's own
     * when something was planned from it, otherwise the current location (the plan's when none is known).
     */
    fun startPointToShow(currentLocation: Coordinates?): Coordinates? =
        if (isPlannedFromStart) startPoint else currentLocation ?: startPoint
}
