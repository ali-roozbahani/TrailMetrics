package dev.roozbahani.trailmetrics.data.local.repository

import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionDao
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_FINISHED
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_PAUSED
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_TRACKING
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore
import dev.roozbahani.trailmetrics.domain.util.Clock

// Room's suspend DAO functions run their queries on the database's query context.
class TrackingSessionStoreImpl(
    private val trackingSessionDao: TrackingSessionDao,
    private val clock: Clock
) : TrackingSessionStore {

    override suspend fun save(state: TrackingState) {
        val (kind, metrics) = when (state) {
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
                savedAtEpochMillis = clock.nowMillis()
            ),
            path = metrics.path
        )
    }

    override suspend fun load(): TrackingState? {
        val session = trackingSessionDao.getSession() ?: return null
        val metrics = TrackingMetrics(
            elapsedMillis = session.elapsedMillis,
            lastUpdateElapsedRealtimeMillis = session.lastUpdateElapsedRealtimeMillis,
            distanceMeters = session.distanceMeters,
            path = trackingSessionDao.getPoints().map { Coordinates(it.latitude, it.longitude) },
            currentSpeedMetersPerSecond = session.currentSpeedMetersPerSecond
        )
        return when (session.stateKind) {
            STATE_TRACKING -> TrackingState.Tracking(metrics)
            STATE_PAUSED -> TrackingState.Paused(metrics)
            STATE_FINISHED -> TrackingState.Finished(metrics)
            else -> error("Unknown stored tracking session state '${session.stateKind}'")
        }
    }

    override suspend fun clear() {
        trackingSessionDao.clear()
    }
}
