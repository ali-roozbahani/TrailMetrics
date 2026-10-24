package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.TrackingState
import kotlin.coroutines.cancellation.CancellationException

/**
 * Keeps the one in-progress tracking session across process death, so the recorded path, distance
 * and elapsed time survive until the session is saved as an activity or discarded.
 */
interface TrackingSessionStore {
    /** Stores [state] as the session. [TrackingState.Idle] is not a session and is ignored. */
    @Throws(Exception::class, CancellationException::class)
    suspend fun save(state: TrackingState)

    /** The stored session as [TrackingState.Tracking], [TrackingState.Paused] or [TrackingState.Finished], or null. */
    @Throws(Exception::class, CancellationException::class)
    suspend fun load(): TrackingState?

    @Throws(Exception::class, CancellationException::class)
    suspend fun clear()
}
