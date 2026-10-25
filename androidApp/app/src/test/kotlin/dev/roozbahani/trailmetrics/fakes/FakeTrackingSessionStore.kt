package dev.roozbahani.trailmetrics.fakes

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore

/** In-memory [TrackingSessionStore] holding one session, with counters for [load] and [clear]. */
class FakeTrackingSessionStore : TrackingSessionStore {
    var stored: TrackingState? = null
    var storedActivityType: ActivityType? = null
    var storedStartedAtEpochMillis: Long? = null
    var loadCalls = 0
        private set
    var clearCalls = 0
        private set

    /** When set, [load] throws it. */
    var loadFailure: Exception? = null

    override suspend fun save(session: StoredTrackingSession) {
        stored = session.state
        storedActivityType = session.activityType
        storedStartedAtEpochMillis = session.startedAtEpochMillis
    }

    override suspend fun load(): StoredTrackingSession? {
        loadCalls++
        loadFailure?.let { throw it }
        return stored?.let { StoredTrackingSession(it, storedActivityType, storedStartedAtEpochMillis) }
    }

    override suspend fun clear() {
        clearCalls++
        stored = null
        storedActivityType = null
        storedStartedAtEpochMillis = null
    }
}
