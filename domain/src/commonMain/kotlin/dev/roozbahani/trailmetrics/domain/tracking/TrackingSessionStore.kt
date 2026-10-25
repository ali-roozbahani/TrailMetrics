package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import kotlin.coroutines.cancellation.CancellationException

/**
 * Keeps the one in-progress tracking session across process death, so the recorded path, distance
 * and elapsed time survive until the session is saved as an activity or discarded.
 */
interface TrackingSessionStore {
    /** Stores [session]. A session whose state is [TrackingState.Idle] is not a session and is ignored. */
    @Throws(Exception::class, CancellationException::class)
    suspend fun save(session: StoredTrackingSession)

    /**
     * The stored session, or null. Its state is [TrackingState.Tracking], [TrackingState.Paused] or
     * [TrackingState.Finished].
     */
    @Throws(Exception::class, CancellationException::class)
    suspend fun load(): StoredTrackingSession?

    @Throws(Exception::class, CancellationException::class)
    suspend fun clear()
}

/**
 * A session as stored: its [state], the [activityType] it was started with and the wall-clock time it
 * started ([startedAtEpochMillis]). Both are null only when unknown: a session stored before they were
 * kept, or a stored type this version does not know.
 */
data class StoredTrackingSession(
    val state: TrackingState,
    val activityType: ActivityType?,
    val startedAtEpochMillis: Long?
)
