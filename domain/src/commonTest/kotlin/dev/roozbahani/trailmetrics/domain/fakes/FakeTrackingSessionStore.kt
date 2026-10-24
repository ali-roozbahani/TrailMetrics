package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore

/** In-memory [TrackingSessionStore]. Every state passed to [save] is kept in [savedStates], in order. */
class FakeTrackingSessionStore : TrackingSessionStore {
    val savedStates = mutableListOf<TrackingState>()
    var stored: TrackingState? = null
    var clearCallCount = 0
        private set

    /** When set, [save] throws it instead of storing the state. */
    var saveFailure: Exception? = null

    /** When set, [clear] throws it instead of clearing. */
    var clearFailure: Exception? = null

    /** When set, [load] throws it. */
    var loadFailure: Exception? = null

    override suspend fun save(state: TrackingState) {
        saveFailure?.let { throw it }
        savedStates += state
        stored = state
    }

    override suspend fun load(): TrackingState? {
        loadFailure?.let { throw it }
        return stored
    }

    override suspend fun clear() {
        clearCallCount++
        clearFailure?.let { throw it }
        stored = null
    }
}
