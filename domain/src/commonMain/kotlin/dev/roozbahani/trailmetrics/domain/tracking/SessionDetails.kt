package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.ActivityType

/**
 * What a [TrackingSessionManager] session was started with, next to its state: the [activityType] and
 * the wall-clock [startedAtEpochMillis]. Both are null only for a restored session that was stored
 * without them.
 */
data class SessionDetails(val activityType: ActivityType?, val startedAtEpochMillis: Long?)
