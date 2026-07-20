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

class TrackingSessionManager(
    private val locationRepository: LocationRepository,
    private val updateTrackingStateUseCase: UpdateTrackingStateUseCase,
    private val trackingServiceLauncher: TrackingServiceLauncher,
    private val clock: Clock,
    private val logger: Logger,
    private val scope: CoroutineScope
) {
    private val _state = MutableStateFlow<TrackingState>(TrackingState.Idle)
    val currentState: StateFlow<TrackingState> = _state.asStateFlow()

    private val _locationIssues = MutableSharedFlow<RouteError>(extraBufferCapacity = 1)
    val locationIssues: SharedFlow<RouteError> = _locationIssues.asSharedFlow()

    private var locationObservationJob: Job? = null

    fun start(startPoint: Coordinates) {
        dispatch(TrackingEvent.Start(startPoint, clock.nowMillis()))
        observeLocation()
        trackingServiceLauncher.start()
    }

    fun pause(){
        locationObservationJob?.cancel()
        dispatch(TrackingEvent.Pause(clock.nowMillis()))
    }

    fun resume() {
        dispatch(TrackingEvent.Resume(clock.nowMillis()))
        observeLocation()
    }

    fun stop(){
        locationObservationJob?.cancel()
        dispatch(TrackingEvent.Stop(clock.nowMillis()))
        trackingServiceLauncher.stop()
    }

    private fun observeLocation() {
        locationObservationJob?.cancel()
        locationObservationJob = scope.launch {
            locationRepository.observeLocationUpdates().collect { update ->
                when (update) {
                    is LocationUpdate.Success -> {
                        dispatch(TrackingEvent.LocationReceived(update.coordinates, clock.nowMillis()))
                    }
                    is LocationUpdate.Unavailable -> {
                        logger.debug(TAG, "Location unavailable: ${update.reason}")
                        _locationIssues.tryEmit(update.reason)
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
    }
}
