package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.TrackingEvent
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
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

    private val _locationIssues = MutableSharedFlow<RouteError>(extraBufferCapacity = 1)
    val locationIssues: SharedFlow<RouteError> = _locationIssues.asSharedFlow()

    private var consecutiveUnavailableCount = 0
    private var locationObservationJob: Job? = null

    // Serializes the store's writes, and guards [clearedState].
    private val storeMutex = Mutex()

    // The state that was current when the stored session was cleared: a save of it still pending
    // in the collector below must not bring the cleared session back.
    private var clearedState: TrackingState? = null

    init {
        // Conflation is fine: the path is cumulative, so the latest state holds everything.
        scope.launch { _state.collect { persist(it) } }
    }

    fun start(startPoint: Coordinates) {
        consecutiveUnavailableCount = 0
        speedCalculator.reset()
        dispatch(TrackingEvent.Start(startPoint, clock.elapsedRealtimeMillis()))
        observeLocation()
        trackingServiceLauncher.start()
    }

    fun pause() {
        locationObservationJob?.cancel()
        dispatch(TrackingEvent.Pause(clock.elapsedRealtimeMillis()))
    }

    fun resume() {
        dispatch(TrackingEvent.Resume(clock.elapsedRealtimeMillis()))
        observeLocation()
    }

    fun stop() {
        locationObservationJob?.cancel()
        dispatch(TrackingEvent.Stop(clock.elapsedRealtimeMillis()))
        trackingServiceLauncher.stop()
    }

    /**
     * Loads the stored session after the process died and makes it the state: a session that was
     * [TrackingState.Tracking] or [TrackingState.Paused] comes back [TrackingState.Paused], because a
     * restored session never records by itself (the gap is not counted and no GPS starts without the
     * user); a [TrackingState.Finished] one stays finished. No location observation and no service
     * launch. With no stored session, or when a session is already running, the state is not replaced.
     */
    @Throws(Exception::class, CancellationException::class)
    suspend fun restore(): TrackingState {
        if (_state.value !is TrackingState.Idle) return _state.value
        val restored = when (val stored = storeMutex.withLock { trackingSessionStore.load() }) {
            null, TrackingState.Idle -> TrackingState.Idle
            is TrackingState.Tracking -> TrackingState.Paused(stored.metrics)
            is TrackingState.Paused -> stored
            is TrackingState.Finished -> stored
        }
        // A session the user started while the load ran is not replaced.
        return if (_state.compareAndSet(TrackingState.Idle, restored)) restored else _state.value
    }

    /**
     * Removes the stored session once its data is safe elsewhere (saved as an activity) or the user
     * discarded it. A failure is logged and not thrown: the session is then offered again by the next
     * restore, which loses nothing.
     */
    suspend fun clearSession() {
        try {
            storeMutex.withLock {
                clearedState = _state.value
                trackingSessionStore.clear()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (expected: Exception) {
            logger.debug(TAG, "Clearing the stored session failed: $expected")
        }
    }

    private suspend fun persist(state: TrackingState) {
        if (state is TrackingState.Idle) return
        try {
            storeMutex.withLock {
                if (state != clearedState) trackingSessionStore.save(state)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (expected: Exception) {
            // No user action can fix a failed write, so it is not a locationIssues-style event; the
            // next state is saved again and tracking goes on.
            logger.debug(TAG, "Saving the session failed: $expected")
        }
    }

    private fun observeLocation() {
        locationObservationJob?.cancel()
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

    private companion object {
        const val TAG = "TrackingSessionManager"
        const val UNAVAILABLE_THRESHOLD = 3
    }
}
