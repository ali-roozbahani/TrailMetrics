package dev.roozbahani.trailmetrics.data.local.repository

import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionDao
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_FINISHED
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_PAUSED
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_TRACKING
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore
import dev.roozbahani.trailmetrics.domain.util.Clock

// Room's suspend DAO functions run their queries on the database's query context.
class TrackingSessionStoreImpl(
    private val trackingSessionDao: TrackingSessionDao,
    private val clock: Clock
) : TrackingSessionStore {

    override suspend fun save(session: StoredTrackingSession) {
        val (kind, metrics) = when (val state = session.state) {
            TrackingState.Idle -> return
            is TrackingState.Tracking -> STATE_TRACKING to state.metrics
            is TrackingState.Paused -> STATE_PAUSED to state.metrics
            is TrackingState.Finished -> STATE_FINISHED to state.metrics
        }
        trackingSessionDao.save(
            session = TrackingSessionEntity(
                stateKind = kind,
                elapsedMillis = metrics.elapsedMillis,
                lastUpdateElapsedRealtimeMillis = metrics.lastUpdateElapsedRealtimeMillis,
                distanceMeters = metrics.distanceMeters,
                currentSpeedMetersPerSecond = metrics.currentSpeedMetersPerSecond,
                savedAtEpochMillis = clock.nowMillis(),
                activityType = session.activityType?.name,
                startedAtEpochMillis = session.startedAtEpochMillis
            ),
            path = metrics.path
        )
    }

    override suspend fun load(): StoredTrackingSession? {
        val session = trackingSessionDao.getSession() ?: return null
        val metrics = TrackingMetrics(
            elapsedMillis = session.elapsedMillis,
            lastUpdateElapsedRealtimeMillis = session.lastUpdateElapsedRealtimeMillis,
            distanceMeters = session.distanceMeters,
            path = trackingSessionDao.getPoints().map { Coordinates(it.latitude, it.longitude) },
            currentSpeedMetersPerSecond = session.currentSpeedMetersPerSecond
        )
        val state = when (session.stateKind) {
            STATE_TRACKING -> TrackingState.Tracking(metrics)
            STATE_PAUSED -> TrackingState.Paused(metrics)
            STATE_FINISHED -> TrackingState.Finished(metrics)
            else -> error("Unknown stored tracking session state '${session.stateKind}'")
        }
        // A name this version does not know (written by a newer one) loads as "type unknown", not as a
        // failure that would keep the session from ever being restored.
        val activityType = ActivityType.entries.firstOrNull { it.name == session.activityType }
        return StoredTrackingSession(state, activityType, session.startedAtEpochMillis)
    }

    override suspend fun clear() {
        trackingSessionDao.clear()
    }
}
