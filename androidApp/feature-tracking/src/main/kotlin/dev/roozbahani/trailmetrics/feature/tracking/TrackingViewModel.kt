package dev.roozbahani.trailmetrics.feature.tracking

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.toUiError
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RouteProgress
import dev.roozbahani.trailmetrics.domain.model.TrackingControls
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.model.availableControls
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.TrackingMetricsUseCase
import dev.roozbahani.trailmetrics.domain.usecase.sessionMetrics
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class TrackingViewModel(
    private val trackingSessionManager: TrackingSessionManager,
    private val userProfileRepository: UserProfileRepository,
    private val trackingMetricsUseCase: TrackingMetricsUseCase,
    private val saveActivityUseCase: SaveActivityUseCase,
    private val activityType: ActivityType,
    private val plannedRoutePoints: List<Coordinates>,
    private val clock: Clock,
    private val snapshotFileDeleter: SnapshotFileDeleter
) : ViewModel() {

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
     * writing a new one. Deleted by [onCleared] if no retry used it: after a failed save the session stays
     * Finished, so no new session starts.
     */
    private val retainedSnapshotPath = MutableStateFlow<String?>(null)

    private val _userProfile = MutableStateFlow<UserProfile?>(null)

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

    init {
        // Raised by the manager at most once per session; it waits as state while no ViewModel exists, and is
        // marked shown once it is in the event channel, which keeps it until the screen collects.
        viewModelScope.launch {
            trackingSessionManager.unsavedSessionWarning.isRaised.filter { it }.collect {
                _events.send(TrackingEvent.ShowSessionNotSaved)
                trackingSessionManager.unsavedSessionWarning.markShown()
            }
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
        trackingSessionManager.routeProgress,
        _userProfile,
        retainedSnapshotPath,
        isRestoring
    ) { trackingState, routeProgress, userProfile, retainedPath, restoring ->
        val calories = trackingMetricsUseCase(trackingState, activityType, userProfile?.weightKg).calories

        TrackingScreenState(
            trackingState = trackingState,
            calories = calories,
            plannedRoutePoints = plannedRoutePoints,
            routeProgress = routeProgress,
            retainedSnapshotPath = retainedPath,
            isRestoring = restoring
        )
    }.stateIn(
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

    private fun start(startCoordinates: Coordinates) {
        // A stored or unsaved session is never replaced: its first save would overwrite the stored one.
        if (!trackingSessionManager.currentState.value.availableControls(isRestoring.value).canStart) return
        isSessionSaved = false
        snapshotInUse = null
        viewModelScope.launch {
            trackingSessionManager.start(startCoordinates, activityType, plannedRoutePoints)
        }
    }

    /**
     * The screen leaves right after Stop (the Stop button and the exit dialog), so the stopped session
     * is discarded: its stored copy is cleared. A session that stops by itself at the route's end is
     * ended by the session manager and stays stored until it is saved with Finish.
     */
    private fun stop() {
        viewModelScope.launch { trackingSessionManager.discard() }
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
                // The session is Finished, so discard() only clears it.
                trackingSessionManager.discard()
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

    /**
     * ATOMIC: [onCleared] deletes a retained file after [viewModelScope] is cancelled, and the launch
     * must still start then. The deleter's delete is not cancellable, so it then completes.
     */
    @OptIn(DelicateCoroutinesApi::class) // ATOMIC is the point: see above
    private fun deleteSnapshotFile(path: String) {
        viewModelScope.launch(start = CoroutineStart.ATOMIC) { snapshotFileDeleter.delete(path) }
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
    /** Set after a Finish that did not save: the screen sends this file again instead of a new one. */
    val retainedSnapshotPath: String? = null,
    /** True until the stored session has been loaded; Start is not offered meanwhile. */
    val isRestoring: Boolean = false
) {
    val currentPath: List<Coordinates>
        get() = trackingState.sessionMetrics()?.path.orEmpty()

    val currentMetrics: TrackingMetrics?
        get() = trackingState.sessionMetrics()

    /** The recorded path the map draws: a line needs two points, so fewer draws nothing. */
    val recordedPathToDraw: List<Coordinates>
        get() = currentPath.takeIf { it.size >= MIN_POINTS_FOR_LINE }.orEmpty()

    /**
     * The traveled segment of the planned route the map draws: only while the recorded path is not drawn
     * (fewer than two points). Once it is, the recorded line alone shows the way travelled, and the planned
     * route stays gray under it; drawing both gave a doubled ring, as the two lines differ a little.
     */
    val traveledSegmentToDraw: List<Coordinates>
        get() = if (recordedPathToDraw.isNotEmpty()) emptyList() else routeProgress?.traveledSegment.orEmpty()

    /** The controls the user may use now: the rules are `domain`'s, this only asks (`availableControls`). */
    private val controls: TrackingControls
        get() = trackingState.availableControls(isRestoring)

    val canStart: Boolean
        get() = controls.canStart

    val canPause: Boolean
        get() = controls.canPause

    val canResume: Boolean
        get() = controls.canResume

    val canStop: Boolean
        get() = controls.canStop

    val canSave: Boolean
        get() = controls.canSave
}

private const val MIN_POINTS_FOR_LINE = 2

/** What the camera does when the recorded path changes. */
enum class CameraPlan { None, FitPath, FollowLastPoint }

/**
 * Decides the camera for [path]. [pathAlreadySeen] is true once a non-empty path has been handled.
 * A restored session arrives with a path of two or more points as its first non-empty path: fit
 * it once. A live session starts with one point, so it is never fitted and follows the last point,
 * as does every later change.
 */
fun cameraPlanFor(path: List<Coordinates>, pathAlreadySeen: Boolean): CameraPlan = when {
    path.isEmpty() -> CameraPlan.None
    !pathAlreadySeen && path.size >= MIN_POINTS_FOR_LINE -> CameraPlan.FitPath
    else -> CameraPlan.FollowLastPoint
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

    /** Saving the in-progress session failed: the recording may not be saved. Once per session. */
    data object ShowSessionNotSaved : TrackingEvent
    data object Saved : TrackingEvent
}
