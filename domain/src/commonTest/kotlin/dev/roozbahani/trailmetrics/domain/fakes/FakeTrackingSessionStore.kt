package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore
import kotlinx.coroutines.CompletableDeferred

/**
 * In-memory [TrackingSessionStore]. Every state passed to [save] is kept in [savedStates], in order, and the
 * type and start time of the last save in [storedActivityType] and [storedStartedAtEpochMillis].
 */
class FakeTrackingSessionStore : TrackingSessionStore {
    val savedStates = mutableListOf<TrackingState>()
    var stored: TrackingState? = null
    var storedActivityType: ActivityType? = null
    var storedStartedAtEpochMillis: Long? = null
    var clearCallCount = 0
        private set

    /** When set, [save] throws it instead of storing the state. */
    var saveFailure: Exception? = null

    /** When set, [clear] throws it instead of clearing. */
    var clearFailure: Exception? = null

    /** When set, [load] suspends until it is completed. */
    var loadGate: CompletableDeferred<Unit>? = null

    /** When set, [load] throws it. */
    var loadFailure: Exception? = null

    override suspend fun save(session: StoredTrackingSession) {
        saveFailure?.let { throw it }
        savedStates += session.state
        stored = session.state
        storedActivityType = session.activityType
        storedStartedAtEpochMillis = session.startedAtEpochMillis
    }

    override suspend fun load(): StoredTrackingSession? {
        loadGate?.await()
        loadFailure?.let { throw it }
        return stored?.let { StoredTrackingSession(it, storedActivityType, storedStartedAtEpochMillis) }
    }

    override suspend fun clear() {
        clearCallCount++
        clearFailure?.let { throw it }
        stored = null
        storedActivityType = null
        storedStartedAtEpochMillis = null
    }
}
