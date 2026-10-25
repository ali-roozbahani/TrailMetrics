package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import kotlin.coroutines.cancellation.CancellationException

/**
 * Keeps the one in-progress tracking session across process death, so the recorded path, distance
 * and elapsed time survive until the session is saved as an activity or discarded.
 */
interface TrackingSessionStore {
    /**
     * Stores [state] and its [activityType] as the session. [TrackingState.Idle] is not a session and
     * is ignored. The type is null only for a session whose type was never known (a restored one
     * stored before the type was kept).
     */
    @Throws(Exception::class, CancellationException::class)
    suspend fun save(state: TrackingState, activityType: ActivityType?)

    /**
     * The stored session, or null. Its state is [TrackingState.Tracking], [TrackingState.Paused] or
     * [TrackingState.Finished].
     */
    @Throws(Exception::class, CancellationException::class)
    suspend fun load(): StoredTrackingSession?

    @Throws(Exception::class, CancellationException::class)
    suspend fun clear()
}

/** A session as stored: its [state] and the [activityType] it was started with, null when unknown. */
data class StoredTrackingSession(val state: TrackingState, val activityType: ActivityType?)
