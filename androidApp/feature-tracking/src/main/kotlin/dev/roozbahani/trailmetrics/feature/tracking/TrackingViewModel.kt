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
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
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
import kotlinx.coroutines.withContext
import java.io.File

class TrackingViewModel(
    private val trackingSessionManager: TrackingSessionManager,
    private val userProfileRepository: UserProfileRepository,
    private val calorieCalculator: CalorieCalculator,
    private val saveActivityUseCase: SaveActivityUseCase,
    private val activityType: ActivityType,
    private val plannedRoutePoints: List<Coordinates>,
    private val clock: Clock,
    ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) : ViewModel() {

    /**
     * Runs the snapshot file deletes. Not [viewModelScope]: [onCleared] deletes a retained file, and
     * by then that scope is cancelled, so a delete launched in it would never run. Each launch is a
     * short, self-completing job; nothing waits for it.
     */
    private val fileScope = CoroutineScope(SupervisorJob() + ioDispatcher)

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
     * writing a new one. Deleted by [onCleared] if no retry used it: after a failed save the session stays Finished, so no new session starts.
     */
    private val retainedSnapshotPath = MutableStateFlow<String?>(null)

    private val _userProfile = MutableStateFlow<UserProfile?>(null)

    private val routeCompletionTracker = RouteCompletionTracker(plannedRoutePoints)

    private val _events = Channel<TrackingEvent>(Channel.BUFFERED)

    /** True until the stored session has been loaded (or the load failed): Start is not offered before. */
    private val isRestoring = MutableStateFlow(true)

    init {
        viewModelScope.launch {
            try {
                // A live session (a new ViewModel over a running manager) is returned as it is, not replaced.
                trackingSessionManager.restore()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _events.send(TrackingEvent.ShowError(RouteUiError.General))
            }
            isRestoring.value = false
        }
    }

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
        retainedSnapshotPath,
        isRestoring
    ) { trackingState, userProfile, retainedPath, restoring ->
        val metrics: TrackingMetrics? = trackingState.sessionMetrics()

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
            retainedSnapshotPath = retainedPath,
            isRestoring = restoring
        )
    }.map(::withRouteCompletion).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000L),
        initialValue = TrackingScreenState(plannedRoutePoints = plannedRoutePoints, isRestoring = true)
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
            TrackingAction.Stop -> stop()
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
        // A stored or unsaved session is never replaced: its first save would overwrite the stored one.
        if (isRestoring.value || trackingSessionManager.currentState.value !is TrackingState.Idle) return
        isSessionSaved = false
        snapshotInUse = null
        viewModelScope.launch {
            trackingSessionManager.start(startCoordinates, activityType)
        }
    }

    /**
     * The screen leaves right after Stop (the Stop button and the exit dialog), so the stopped session
     * is discarded: its stored copy is cleared. A session that stops by itself at the route's end is
     * stopped by [withRouteCompletion] and stays stored until it is saved with Finish.
     */
    private fun stop() {
        trackingSessionManager.stop()
        viewModelScope.launch { clearStoredSession() }
    }

    /** Not cancelled with the ViewModel: the screen leaves right after, and a half-done clear keeps the session. */
    private suspend fun clearStoredSession() {
        withContext(NonCancellable) { trackingSessionManager.clearSession() }
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
        val startedAtEpochMillis = trackingSessionManager.sessionDetails.value?.startedAtEpochMillis
            // A session stored by an older version has no start time: this is an estimate, the wall clock now
            // minus the time the session ran.
            ?: (clock.nowMillis() - finishedState.metrics.elapsedMillis)
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
                // Only now is the recorded data safe elsewhere; a failed save above keeps the stored session.
                clearStoredSession()
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
        fileScope.launch { File(path).delete() }
    }

    override fun onCleared() {
        retainedSnapshotPath.value?.let(::deleteSnapshotFile)
        super.onCleared()
    }

    private suspend fun readProfileAgain(): UserProfile? =
        userProfileRepository.getUserProfile().also { _userProfile.value = it }
}

/** The metrics of a session that exists, running, paused or finished; null while idle. */
private fun TrackingState.sessionMetrics(): TrackingMetrics? = when (this) {
    is TrackingState.Tracking -> metrics
    is TrackingState.Paused -> metrics
    is TrackingState.Finished -> metrics
    TrackingState.Idle -> null
}

/** Named to avoid colliding with the domain [TrackingState] it wraps. */
data class TrackingScreenState(
    val trackingState: TrackingState = TrackingState.Idle,
    val calories: Double? = null,
    val plannedRoutePoints: List<Coordinates> = emptyList(),
    val routeProgress: RouteProgress? = null,
    val hasReachedDestination: Boolean = false,
    /** Set after a Finish that did not save: the screen sends this file again instead of a new one. */
    val retainedSnapshotPath: String? = null,
    /** True until the stored session has been loaded; Start is not offered meanwhile. */
    val isRestoring: Boolean = false
) {
    val currentPath: List<Coordinates>
        get() = trackingState.sessionMetrics()?.path.orEmpty()

    val currentMetrics: TrackingMetrics?
        get() = trackingState.sessionMetrics()

    /** Only in Idle, and once the stored session is loaded: Start must never replace a session that exists. */
    val canStart: Boolean
        get() = trackingState is TrackingState.Idle && !isRestoring

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
