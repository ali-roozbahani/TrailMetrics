package dev.roozbahani.trailmetrics.feature.tracking

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.RouteUiErrorMapper
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class TrackingViewModel(
    private val trackingSessionManager: TrackingSessionManager,
    private val uiErrorMapper: RouteUiErrorMapper
) : ViewModel() {

    val uiState: StateFlow<TrackingUiState> = trackingSessionManager.currentState
        .map { trackingState ->
            TrackingUiState(trackingState = trackingState)
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000L),
            initialValue = TrackingUiState()
        )

    val uiEvents: Flow<TrackingUiEvent> = trackingSessionManager.locationIssues
        .map { routeError ->
            if (routeError is RouteError.MissingLocationPermission) {
                TrackingUiEvent.RequestLocationPermission
            } else {
                TrackingUiEvent.ShowError(uiErrorMapper.map(routeError))
            }
        }

    fun onStartClicked(startCoordinates: Coordinates) {
        viewModelScope.launch {
            trackingSessionManager.start(startCoordinates)
        }
    }

    fun onPauseClicked() = trackingSessionManager.pause()

    fun onResumeClicked() = trackingSessionManager.resume()

    fun onStopClicked() = trackingSessionManager.stop()

    fun onLocationPermissionGranted(startCoordinates: Coordinates) {
        onStartClicked(startCoordinates)
    }

}

data class TrackingUiState(
    val trackingState: TrackingState = TrackingState.Idle
) {
    val currentPath: List<Coordinates>
        get() = when (val state = trackingState) {
            is TrackingState.Tracking -> state.metrics.path
            is TrackingState.Paused -> state.metrics.path
            else -> emptyList()
        }

    val currentMetrics: TrackingMetrics?
        get() = when (trackingState) {
            is TrackingState.Tracking -> trackingState.metrics
            is TrackingState.Paused -> trackingState.metrics
            else -> null
        }

    val canStart: Boolean
        get() = (trackingState is TrackingState.Idle || trackingState is TrackingState.Finished)

    val canPause: Boolean
        get() = trackingState is TrackingState.Tracking

    val canResume: Boolean
        get() = trackingState is TrackingState.Paused

    val canStop: Boolean
        get() = trackingState is TrackingState.Tracking || trackingState is TrackingState.Paused
}

sealed interface TrackingUiEvent {
    data object RequestLocationPermission : TrackingUiEvent
    data class ShowError(val error: RouteUiError) : TrackingUiEvent
}
