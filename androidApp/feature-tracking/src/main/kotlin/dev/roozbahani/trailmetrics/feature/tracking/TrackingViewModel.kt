package dev.roozbahani.trailmetrics.feature.tracking

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.toUiError
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RouteProgress
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class TrackingViewModel(
    private val trackingSessionManager: TrackingSessionManager,
    private val userProfileRepository: UserProfileRepository,
    private val calorieCalculator: CalorieCalculator,
    private val saveActivityUseCase: SaveActivityUseCase,
    private val activityType: ActivityType,
    private val plannedRoutePoints: List<Coordinates>,
    private val clock: Clock
) : ViewModel() {

    private var startedAtEpochMillis: Long = 0L

    /**
     * Set synchronously by [finish] before the save is launched, so a second Finish (a double tap)
     * can't save the session again. Cleared by [start] for a new session, and if the save throws.
     */
    private var isSessionSaved = false

    private val _userProfile = MutableStateFlow<UserProfile?>(null)

    private val routeCompletionTracker = RouteCompletionTracker(plannedRoutePoints)

    private val _events = Channel<TrackingEvent>(Channel.BUFFERED)

    init {
        viewModelScope.launch {
            _userProfile.value = userProfileRepository.getUserProfile()
        }
    }

    val state: StateFlow<TrackingScreenState> = combine(
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

        TrackingScreenState(
            trackingState = trackingState,
            calories = calories,
            plannedRoutePoints = plannedRoutePoints
        )
    }.map(::withRouteCompletion).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000L),
        initialValue = TrackingScreenState(plannedRoutePoints = plannedRoutePoints)
    )

    // Location issues keep the session manager's SharedFlow delivery (dropped while nothing
    // collects); only events the ViewModel originates go through the Channel.
    val events: Flow<TrackingEvent> = merge(
        _events.receiveAsFlow(),
        trackingSessionManager.locationIssues.map { routeError ->
            if (routeError is RouteError.MissingLocationPermission) {
                TrackingEvent.RequestLocationPermission
            } else {
                TrackingEvent.ShowError(routeError.toUiError())
            }
        }
    )

    fun onAction(action: TrackingAction) {
        when (action) {
            is TrackingAction.Start -> start(action.startCoordinates)
            is TrackingAction.LocationPermissionGranted -> start(action.startCoordinates)
            TrackingAction.Pause -> trackingSessionManager.pause()
            TrackingAction.Resume -> trackingSessionManager.resume()
            TrackingAction.Stop -> trackingSessionManager.stop()
            is TrackingAction.Finish -> finish(action.snapshotFilePath)
        }
    }

    /**
     * Route progress and the auto-stop at the route's end. This runs inside the state pipeline,
     * so, like the composable effect it replaces, it is evaluated only while the screen observes
     * state (plus the WhileSubscribed grace period).
     */
    private fun withRouteCompletion(state: TrackingScreenState): TrackingScreenState {
        if (routeCompletionTracker.onUpdate(state.currentPath.lastOrNull(), state.trackingState)) {
            trackingSessionManager.stop()
        }
        return state.copy(
            routeProgress = routeCompletionTracker.progress,
            hasReachedDestination = routeCompletionTracker.hasReachedDestination
        )
    }

    private fun start(startCoordinates: Coordinates) {
        startedAtEpochMillis = clock.nowMillis()
        isSessionSaved = false
        viewModelScope.launch {
            trackingSessionManager.start(startCoordinates)
        }
    }

    private fun finish(snapshotFilePath: String?) {
        if (isSessionSaved) return
        val finishedState = trackingSessionManager.currentState.value as? TrackingState.Finished ?: return
        val weightKg = _userProfile.value?.weightKg ?: return
        isSessionSaved = true
        viewModelScope.launch {
            runCatching {
                saveActivityUseCase(
                    activityType = activityType,
                    plannedRoutePoints = plannedRoutePoints,
                    metrics = finishedState.metrics,
                    weightKg = weightKg,
                    startedAtEpochMillis = startedAtEpochMillis,
                    snapshotFilePath = snapshotFilePath
                )
            }.onFailure {
                // Let the user retry; the failure itself still propagates.
                isSessionSaved = false
            }.getOrThrow()
            _events.send(TrackingEvent.Saved)
        }
    }
}

/** Named to avoid colliding with the domain [TrackingState] it wraps. */
data class TrackingScreenState(
    val trackingState: TrackingState = TrackingState.Idle,
    val calories: Double? = null,
    val plannedRoutePoints: List<Coordinates> = emptyList(),
    val routeProgress: RouteProgress? = null,
    val hasReachedDestination: Boolean = false
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

sealed interface TrackingAction {
    data class Start(val startCoordinates: Coordinates) : TrackingAction
    data class LocationPermissionGranted(val startCoordinates: Coordinates) : TrackingAction
    data object Pause : TrackingAction
    data object Resume : TrackingAction
    data object Stop : TrackingAction
    data class Finish(val snapshotFilePath: String?) : TrackingAction
}

sealed interface TrackingEvent {
    data object RequestLocationPermission : TrackingEvent
    data class ShowError(val error: RouteUiError) : TrackingEvent
    data object Saved : TrackingEvent
}
