package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RouteProgress
import dev.roozbahani.trailmetrics.domain.model.TrackingEvent
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException

class TrackingSessionManager(
    private val locationRepository: LocationRepository,
    private val updateTrackingStateUseCase: UpdateTrackingStateUseCase,
    private val trackingServiceLauncher: TrackingServiceLauncher,
    private val speedCalculator: SpeedCalculator,
    private val clock: Clock,
    private val logger: Logger,
    private val trackingSessionStore: TrackingSessionStore,
    private val scope: CoroutineScope
) {
    private val _state = MutableStateFlow<TrackingState>(TrackingState.Idle)
    val currentState: StateFlow<TrackingState> = _state.asStateFlow()

    private val _sessionDetails = MutableStateFlow<SessionDetails?>(null)

    /**
     * The activity type, start time and planned route of the current session: set by [start] and by
     * [restore], null while idle.
     */
    val sessionDetails: StateFlow<SessionDetails?> = _sessionDetails.asStateFlow()

    private val _routeProgress = MutableStateFlow<RouteProgress?>(null)

    /**
     * Progress along the planned route after the latest fix of the session; null before the first fix, for
     * a session without a plan and while there is no session (after [clearSession] or [discard]; a finished
     * session that is not cleared keeps its progress). The manager ends the session by itself when the
     * route's end is reached.
     */
    val routeProgress: StateFlow<RouteProgress?> = _routeProgress.asStateFlow()

    private val _locationIssues = MutableSharedFlow<RouteError>(extraBufferCapacity = 1)
    val locationIssues: SharedFlow<RouteError> = _locationIssues.asSharedFlow()

    private val _unsavedSessionWarning = MutableStateFlow(false)

    /**
     * True from the first failed save of the current session until a screen has shown it and called
     * [onUnsavedSessionWarningShown]: the recording may be lost if the process dies (owner decision of
     * 2026-11-25). State and not a one-shot event, so it waits while no screen collects (tracking with the
     * screen off). Raised at most once per session, not on every failed write; [start] clears it.
     */
    val unsavedSessionWarning: StateFlow<Boolean> = _unsavedSessionWarning.asStateFlow()

    // Whether this session already raised [unsavedSessionWarning]; reset by [start].
    private val hasWarnedOfUnsavedSession = MutableStateFlow(false)

    private var consecutiveUnavailableCount = 0
    private var locationObservationJob: Job? = null

    // The route-completion rule of the current session. start() and restore() replace it as a whole, and
    // observeLocation() hands the value it reads to its collector, which never reads this field itself: a
    // collector that is still winding down when a new session starts keeps its own session's tracker.
    private var routeCompletion = SessionRouteCompletion(RouteCompletionTracker(emptyList()), hasPlan = false)

    // Serializes the store's writes, and guards [clearedState].
    private val storeMutex = Mutex()

    // The state that was current when the stored session was cleared: a save of it still pending
    // in the collector below must not bring the cleared session back.
    private var clearedState: TrackingState? = null

    // Set when a Finished session was discarded from memory: a row left behind by a failed clear is for
    // the next process to restore, not this one, or the saved session would come back as a Finished card.
    private val isSessionDiscarded = MutableStateFlow(false)

    init {
        // Conflation is fine: the path is cumulative, so the latest state holds everything.
        scope.launch { _state.collect { persist(it) } }
    }

    fun start(startPoint: Coordinates, activityType: ActivityType) {
        start(startPoint, activityType, emptyList())
    }

    /** As [start], for a session on [plannedRoute]; the plan is in [sessionDetails] and stored with the session. */
    fun start(startPoint: Coordinates, activityType: ActivityType, plannedRoute: List<Coordinates>) {
        consecutiveUnavailableCount = 0
        hasWarnedOfUnsavedSession.value = false
        _unsavedSessionWarning.value = false
        _sessionDetails.value = SessionDetails(activityType, clock.nowMillis(), plannedRoute)
        speedCalculator.reset()
        routeCompletion = SessionRouteCompletion(
            tracker = RouteCompletionTracker(plannedRoute),
            hasPlan = plannedRoute.isNotEmpty()
        )
        _routeProgress.value = null
        dispatch(TrackingEvent.Start(startPoint, clock.elapsedRealtimeMillis()))
        observeLocation()
        trackingServiceLauncher.start()
    }

    fun pause() {
        locationObservationJob?.cancel()
        dispatch(TrackingEvent.Pause(clock.elapsedRealtimeMillis()))
    }

    /**
     * Starts the service launcher as [start] does: a session restored after process death has no service,
     * and in a live session the launcher is started a second time, which both launchers allow.
     */
    fun resume() {
        dispatch(TrackingEvent.Resume(clock.elapsedRealtimeMillis()))
        observeLocation()
        trackingServiceLauncher.start()
    }

    /** Ends the session; does nothing when it is [TrackingState.Idle] or already [TrackingState.Finished]. */
    fun stop() {
        if (_state.value is TrackingState.Idle || _state.value is TrackingState.Finished) return
        locationObservationJob?.cancel()
        dispatch(TrackingEvent.Stop(clock.elapsedRealtimeMillis()))
        trackingServiceLauncher.stop()
    }

    /**
     * Loads the stored session after the process died and makes it the state: a session that was
     * [TrackingState.Tracking] or [TrackingState.Paused] comes back [TrackingState.Paused], because a
     * restored session never records by itself (the gap is not counted and no GPS starts without the
     * user); a [TrackingState.Finished] one stays finished. No location observation and no service
     * launch. The session's type, start time and planned route are then in [sessionDetails]. With no stored
     * session, or when a session is already running, the state is not replaced.
     */
    @Throws(Exception::class, CancellationException::class)
    suspend fun restore(): TrackingState {
        if (_state.value !is TrackingState.Idle || isSessionDiscarded.value) return _state.value
        val stored = storeMutex.withLock { trackingSessionStore.load() }
        val restored = when (val storedState = stored?.state) {
            null, TrackingState.Idle -> TrackingState.Idle
            is TrackingState.Tracking -> TrackingState.Paused(storedState.metrics)
            is TrackingState.Paused -> storedState
            is TrackingState.Finished -> storedState
        }
        // A session the user started while the load ran is not replaced. The details are set first: the
        // state change below is saved with them.
        if (stored != null && restored !is TrackingState.Idle) {
            _sessionDetails.compareAndSet(
                null,
                SessionDetails(stored.activityType, stored.startedAtEpochMillis, stored.plannedRoute)
            )
        }
        if (_state.compareAndSet(TrackingState.Idle, restored)) {
            if (restored !is TrackingState.Idle) {
                val plan = stored?.plannedRoute.orEmpty()
                routeCompletion = SessionRouteCompletion(RouteCompletionTracker(plan), plan.isNotEmpty())
                _routeProgress.value = null
            }
            return restored
        }
        return _state.value
    }

    /**
     * Removes the stored session once its data is safe elsewhere (saved as an activity) or the user
     * discarded it, and returns a [TrackingState.Finished] session to [TrackingState.Idle] (with no
     * [sessionDetails] and no [routeProgress]) so the next session can start. A running or paused session
     * keeps its state.
     * The in-memory session is discarded even when the store fails: that failure is logged and not
     * thrown, and the next process's restore offers the stored row again, which loses nothing; this
     * manager's own [restore] no longer does.
     */
    suspend fun clearSession() {
        var clearing: TrackingState = TrackingState.Idle
        try {
            storeMutex.withLock {
                clearing = _state.value
                clearedState = clearing
                trackingSessionStore.clear()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (expected: Exception) {
            logger.debug(TAG, "Clearing the stored session failed: $expected")
        }
        // Compare-and-set: a session started while the clear ran is not touched.
        if (clearing is TrackingState.Finished) {
            val details = _sessionDetails.value
            if (_state.compareAndSet(clearing, TrackingState.Idle)) {
                isSessionDiscarded.value = true
                _sessionDetails.compareAndSet(details, null)
                // No session, no progress: the next screen must not show this session's traveled segment.
                _routeProgress.value = null
            }
        }
    }

    /**
     * Ends the session the user does not want: [stop] (skipped when it is already [TrackingState.Finished]),
     * then [clearSession]. The clear is not cancelled with the caller, because a half-done clear keeps the
     * session, and the caller (a screen that is left, an Activity that is recreated) is often gone by then.
     */
    @Throws(Exception::class, CancellationException::class)
    suspend fun discard() {
        if (_state.value !is TrackingState.Finished) stop()
        withContext(NonCancellable) { clearSession() }
    }

    private suspend fun persist(state: TrackingState) {
        if (state is TrackingState.Idle) return
        try {
            storeMutex.withLock {
                if (state != clearedState) {
                    val details = _sessionDetails.value
                    trackingSessionStore.save(
                        StoredTrackingSession(
                            state,
                            details?.activityType,
                            details?.startedAtEpochMillis,
                            details?.plannedRoute.orEmpty()
                        )
                    )
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (expected: Exception) {
            // Tracking goes on and the next state is saved again; the user is told once per session that the
            // recording may not be saved ([unsavedSessionWarning]).
            logger.debug(TAG, "Saving the session failed: $expected")
            if (hasWarnedOfUnsavedSession.compareAndSet(expect = false, update = true)) {
                _unsavedSessionWarning.value = true
            }
        }
    }

    /** A screen has shown [unsavedSessionWarning]: it is not raised again for this session. */
    fun onUnsavedSessionWarningShown() {
        _unsavedSessionWarning.value = false
    }

    private fun observeLocation() {
        locationObservationJob?.cancel()
        val sessionRouteCompletion = routeCompletion
        locationObservationJob = scope.launch {
            locationRepository.observeLocationUpdates().collect { update ->
                when (update) {
                    is LocationUpdate.Success -> {
                        consecutiveUnavailableCount = 0
                        val speed = speedCalculator.calculate(
                            coordinates = update.coordinates,
                            elapsedRealtimeMillis = clock.elapsedRealtimeMillis(),
                            reportedSpeedMetersPerSecond = update.speedMetersPerSecond,
                            accuracyMeters = update.accuracyMeters
                        )
                        dispatch(
                            TrackingEvent.LocationReceived(
                                coordinates = update.coordinates,
                                elapsedRealtimeMillis = clock.elapsedRealtimeMillis(),
                                speedMetersPerSecond = speed
                            )
                        )
                        val completion = sessionRouteCompletion.tracker.update(update.coordinates, _state.value)
                        if (sessionRouteCompletion.hasPlan) _routeProgress.value = completion.progress
                        if (completion.reachedNow) stop()
                    }

                    is LocationUpdate.Unavailable -> {
                        consecutiveUnavailableCount++
                        logger.debug(TAG, "Location unavailable: ${update.reason}")
                        if (consecutiveUnavailableCount >= UNAVAILABLE_THRESHOLD) {
                            _locationIssues.tryEmit(update.reason)
                        }
                    }
                }
            }
        }
    }

    private fun dispatch(newEvent: TrackingEvent) {
        _state.update { updateTrackingStateUseCase(it, newEvent) }
    }

    /** One session's [tracker] and whether it has a plan; immutable, so a collector can hold it safely. */
    private class SessionRouteCompletion(val tracker: RouteCompletionTracker, val hasPlan: Boolean)

    private companion object {
        const val TAG = "TrackingSessionManager"
        const val UNAVAILABLE_THRESHOLD = 3
    }
}
