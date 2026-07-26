package dev.roozbahani.trailmetrics.feature.tracking

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.RouteUiErrorMapper
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class TrackingViewModel(
    private val trackingSessionManager: TrackingSessionManager,
    private val userProfileRepository: UserProfileRepository,
    private val calorieCalculator: CalorieCalculator,
    private val activityType: ActivityType,
    private val uiErrorMapper: RouteUiErrorMapper
) : ViewModel() {

    private val _userProfile = MutableStateFlow<UserProfile?>(null)

    init {
        viewModelScope.launch {
            _userProfile.value = userProfileRepository.getUserProfile()
        }
    }

    val uiState: StateFlow<TrackingUiState> = combine(
        trackingSessionManager.currentState,
        _userProfile
    ) { trackingState, userProfile ->
        val metrics: TrackingMetrics? = when (trackingState) {
            is TrackingState.Tracking -> trackingState.metrics
            is TrackingState.Paused -> trackingState.metrics
            else -> null
        }

        val calories: Double? = if (metrics != null && userProfile != null) {
            metrics.averageSpeedMetersPerSecond?.let { averageSpeed ->
                calorieCalculator.calculate(
                    activityType = activityType,
                    averageSpeedMetersPerSecond = averageSpeed,
                    weightKg = userProfile.weightKg,
                    durationMillis = metrics.elapsedMillis
                )
            }
        } else null

        TrackingUiState(trackingState = trackingState, calories = calories)
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
    val trackingState: TrackingState = TrackingState.Idle,
    val calories: Double? = null
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
