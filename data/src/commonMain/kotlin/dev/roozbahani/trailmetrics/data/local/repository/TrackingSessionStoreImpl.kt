package dev.roozbahani.trailmetrics.data.local.repository

import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionDao
import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionPlanDao
import dev.roozbahani.trailmetrics.data.local.database.WriteTransaction
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_FINISHED
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_PAUSED
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.STATE_TRACKING
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.TRACKING_SESSION_ID
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionPlanPointEntity
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore
import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

// Every storage access switches to [ioDispatcher] itself, so a caller never depends on the context Room runs its
// queries on. The extra switch is free where the caller is already on that dispatcher (the database's query
// context is the same dispatcher, so Room's own switch becomes a no-op) and cheap from `Dispatchers.Default`.
class TrackingSessionStoreImpl(
    private val trackingSessionDao: TrackingSessionDao,
    private val trackingSessionPlanDao: TrackingSessionPlanDao,
    private val writeTransaction: WriteTransaction,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher
) : TrackingSessionStore {

    // What the plan table holds, once known: save runs on every location fix, and its answer is the same until
    // the session changes. The manager serializes save, load and clear (its store mutex).
    private data class StoredPlan(val startedAtEpochMillis: Long?, val size: Int)

    private var storedPlan: StoredPlan? = null

    override suspend fun save(session: StoredTrackingSession) = withContext(ioDispatcher) {
        val (kind, metrics) = when (val state = session.state) {
            TrackingState.Idle -> return@withContext
            is TrackingState.Tracking -> STATE_TRACKING to state.metrics
            is TrackingState.Paused -> STATE_PAUSED to state.metrics
            is TrackingState.Finished -> STATE_FINISHED to state.metrics
        }
        val entity = TrackingSessionEntity(
            stateKind = kind,
            elapsedMillis = metrics.elapsedMillis,
            lastUpdateElapsedRealtimeMillis = metrics.lastUpdateElapsedRealtimeMillis,
            distanceMeters = metrics.distanceMeters,
            currentSpeedMetersPerSecond = metrics.currentSpeedMetersPerSecond,
            savedAtEpochMillis = clock.nowMillis(),
            activityType = session.activityType?.name,
            startedAtEpochMillis = session.startedAtEpochMillis
        )
        val plan = session.plannedRoute
        val wanted = StoredPlan(entity.startedAtEpochMillis, plan.size)
        val replacePlan = (storedPlan ?: readStoredPlan()) != wanted
        // One transaction: a changed plan is deleted, the session row saved (the plan's foreign key needs the
        // row) and the plan inserted, or none of it, so a failure leaves the previous session with its plan.
        writeTransaction.run {
            if (replacePlan) {
                storedPlan = null
                trackingSessionPlanDao.deleteAll()
            }
            trackingSessionDao.save(session = entity, path = metrics.path)
            if (replacePlan) {
                trackingSessionPlanDao.insert(
                    plan.mapIndexed { index, point ->
                        TrackingSessionPlanPointEntity(TRACKING_SESSION_ID, index, point.latitude, point.longitude)
                    }
                )
            }
        }
        storedPlan = wanted
    }

    // The plan is written once per session: it is the stored one while the session started at the same time
    // (a session always gets a new start time) and the number of points is the same.
    private suspend fun readStoredPlan(): StoredPlan? {
        val session = trackingSessionDao.getSession() ?: return null
        return StoredPlan(session.startedAtEpochMillis, trackingSessionPlanDao.count())
    }

    override suspend fun load(): StoredTrackingSession? = withContext(ioDispatcher) {
        val session = trackingSessionDao.getSession() ?: return@withContext null
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
        val plannedRoute = trackingSessionPlanDao.getAll().map { Coordinates(it.latitude, it.longitude) }
        storedPlan = StoredPlan(session.startedAtEpochMillis, plannedRoute.size)
        StoredTrackingSession(state, activityType, session.startedAtEpochMillis, plannedRoute)
    }

    override suspend fun clear() = withContext(ioDispatcher) {
        storedPlan = null
        trackingSessionDao.clear()
    }
}
