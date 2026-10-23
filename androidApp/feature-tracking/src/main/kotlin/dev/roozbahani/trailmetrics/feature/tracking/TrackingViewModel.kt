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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
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
import java.io.File

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
     * can't save the session again. Cleared by [start] for a new session, and if the save fails.
     */
    private var isSessionSaved = false

    /**
     * The snapshot file of the Finish whose save is running or has succeeded: a saved activity
     * references it, so it is never deleted. Cleared by [start].
     */
    private var snapshotInUse: String? = null

    /**
     * The snapshot file kept after a Finish that did not save, so the retry reuses it instead of
     * writing a new one. Deleted by [start] and [onCleared] if no retry used it.
     */
    private val retainedSnapshotPath = MutableStateFlow<String?>(null)

    private val _userProfile = MutableStateFlow<UserProfile?>(null)

    private val routeCompletionTracker = RouteCompletionTracker(plannedRoutePoints)

    private val _events = Channel<TrackingEvent>(Channel.BUFFERED)

    private val initialProfileLoad: Job = viewModelScope.launch {
        try {
            _userProfile.value = userProfileRepository.getUserProfile()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Without a profile there are no calories; Finish reads the profile again.
            _events.send(TrackingEvent.ShowError(RouteUiError.General))
        }
    }

    val state: StateFlow<TrackingScreenState> = combine(
        trackingSessionManager.currentState,
        _userProfile,
        retainedSnapshotPath
    ) { trackingState, userProfile, retainedPath ->
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
            plannedRoutePoints = plannedRoutePoints,
            retainedSnapshotPath = retainedPath
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
        snapshotInUse = null
        // The session whose save failed is discarded; nothing can retry with its file.
        retainedSnapshotPath.value?.let(::deleteSnapshotFile)
        retainedSnapshotPath.value = null
        viewModelScope.launch {
            trackingSessionManager.start(startCoordinates)
        }
    }

    private fun finish(snapshotFilePath: String?) {
        val finishedState = trackingSessionManager.currentState.value as? TrackingState.Finished
        val loadedProfile = _userProfile.value
        // The first load is still running: Finish does nothing, as before, and a later tap works.
        val isProfileLoading = loadedProfile == null && initialProfileLoad.isActive
        if (isSessionSaved || finishedState == null || isProfileLoading) {
            deleteIfUnreferenced(snapshotFilePath)
            return
        }
        // A retry reuses the file the failed Finish kept; a file handed in again is surplus.
        val path = retainedSnapshotPath.value ?: snapshotFilePath
        snapshotInUse = path
        retainedSnapshotPath.value = null
        isSessionSaved = true
        deleteIfUnreferenced(snapshotFilePath)
        viewModelScope.launch {
            try {
                val userProfile = loadedProfile ?: readProfileAgain()
                if (userProfile == null) {
                    // Nothing is saved or discarded; the user can tap Finish again.
                    keepForRetry(path)
                    _events.send(TrackingEvent.ShowError(RouteUiError.General))
                    return@launch
                }
                saveActivityUseCase(
                    activityType = activityType,
                    plannedRoutePoints = plannedRoutePoints,
                    metrics = finishedState.metrics,
                    weightKg = userProfile.weightKg,
                    startedAtEpochMillis = startedAtEpochMillis,
                    snapshotFilePath = path
                )
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Let the user retry.
                keepForRetry(path)
                _events.send(TrackingEvent.ShowError(RouteUiError.General))
                return@launch
            }
            _events.send(TrackingEvent.Saved)
        }
    }

    private fun keepForRetry(snapshotFilePath: String?) {
        isSessionSaved = false
        snapshotInUse = null
        retainedSnapshotPath.value = snapshotFilePath
    }

    /** The screen only produces snapshot files; whether one is kept or deleted is decided here. */
    private fun deleteIfUnreferenced(snapshotFilePath: String?) {
        if (snapshotFilePath != null &&
            snapshotFilePath != snapshotInUse &&
            snapshotFilePath != retainedSnapshotPath.value
        ) {
            deleteSnapshotFile(snapshotFilePath)
        }
    }

    private fun deleteSnapshotFile(path: String) {
        File(path).delete()
    }

    override fun onCleared() {
        retainedSnapshotPath.value?.let(::deleteSnapshotFile)
        super.onCleared()
    }

    private suspend fun readProfileAgain(): UserProfile? =
        userProfileRepository.getUserProfile().also { _userProfile.value = it }
}

/** Named to avoid colliding with the domain [TrackingState] it wraps. */
data class TrackingScreenState(
    val trackingState: TrackingState = TrackingState.Idle,
    val calories: Double? = null,
    val plannedRoutePoints: List<Coordinates> = emptyList(),
    val routeProgress: RouteProgress? = null,
    val hasReachedDestination: Boolean = false,
    /** Set after a Finish that did not save: the screen sends this file again instead of a new one. */
    val retainedSnapshotPath: String? = null
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
