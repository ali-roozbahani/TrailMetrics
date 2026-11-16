package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates

/**
 * What a [TrackingSessionManager] session was started with, next to its state: the [activityType] and
 * the wall-clock [startedAtEpochMillis]. Both are null only for a restored session that was stored
 * without them. [plannedRoute] is the route the session was started on, empty when it was started
 * without one or stored before the plan was kept.
 */
data class SessionDetails(
    val activityType: ActivityType?,
    val startedAtEpochMillis: Long?,
    val plannedRoute: List<Coordinates> = emptyList()
)
