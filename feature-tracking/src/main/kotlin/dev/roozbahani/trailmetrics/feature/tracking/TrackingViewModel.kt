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
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class TrackingViewModel(
    private val trackingSessionManager: TrackingSessionManager,
    private val getCurrentLocationUseCase: GetCurrentLocationUseCase,
    private val uiErrorMapper: RouteUiErrorMapper
) : ViewModel() {

    private val _isPreparingStart = MutableStateFlow(false)

    val uiState: StateFlow<TrackingUiState> = combine(
        trackingSessionManager.currentState,
        _isPreparingStart
    ) { trackingState, isPreparingStart ->
        TrackingUiState(trackingState = trackingState, isPreparingStart = isPreparingStart)
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000L),
        initialValue = TrackingUiState()
    )

    private val _uiEvents = Channel<TrackingUiEvent>(Channel.BUFFERED)
    val uiEvents: Flow<TrackingUiEvent> = _uiEvents.receiveAsFlow()

    fun onStartClicked() {
        viewModelScope.launch {
            _isPreparingStart.update { true }
            getCurrentLocationUseCase()
                .onSuccess { coordinates ->
                    trackingSessionManager.start(coordinates)
                }
                .onFailure { error ->
                    _uiEvents.send(TrackingUiEvent.ShowError(uiErrorMapper.map(error as? RouteError)))
                    if (error is RouteError.MissingLocationPermission) {
                        _uiEvents.send(TrackingUiEvent.RequestLocationPermission)
                    }
                }
            _isPreparingStart.update { false }
        }
    }

    fun onPauseClicked() = trackingSessionManager.pause()

    fun onResumeClicked() = trackingSessionManager.resume()

    fun onStopClicked() = trackingSessionManager.stop()

    fun onLocationPermissionGranted() {
        onStartClicked()
    }

}

data class TrackingUiState(
    val trackingState: TrackingState = TrackingState.Idle,
    val isPreparingStart: Boolean = false
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
        get() = (trackingState is TrackingState.Idle || trackingState is TrackingState.Finished) && !isPreparingStart

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
