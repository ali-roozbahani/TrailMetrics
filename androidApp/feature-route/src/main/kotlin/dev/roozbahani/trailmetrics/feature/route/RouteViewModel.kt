package dev.roozbahani.trailmetrics.feature.route

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.toUiError
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteDraft
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class RouteViewModel(
    private val getCurrentLocationUseCase: GetCurrentLocationUseCase,
    private val generateClosedRouteUseCase: GenerateClosedRouteUseCase,
    private val userProfileRepository: UserProfileRepository
) : ViewModel() {

    private val _state = MutableStateFlow(RouteState())
    val state: StateFlow<RouteState> = _state.asStateFlow()

    private val _events = Channel<RouteEvent>(Channel.BUFFERED)
    val events: Flow<RouteEvent> = _events.receiveAsFlow()

    init {
        loadCurrentLocation()
        getAndUpdateUserProfile()
    }

    fun onAction(action: RouteAction) {
        when (action) {
            is RouteAction.MapTapped -> addWaypoint(action.coordinates)
            is RouteAction.WaypointRemoved -> removeWaypoint(action.waypoint)
            is RouteAction.ActivityTypeSelected -> _state.update { it.copy(selectedActivityType = action.activityType) }
            is RouteAction.UserProfileSaved -> saveUserProfile(action.weightKg)
            RouteAction.GenerateRouteClicked -> generateRoute()
            RouteAction.ResetClicked -> reset()
            RouteAction.StartTrackingClicked -> startTracking()
            RouteAction.LocationPermissionGranted -> loadCurrentLocation()
        }
    }

    private fun loadCurrentLocation() {
        viewModelScope.launch {
            try {
                val coordinates = getCurrentLocationUseCase()
                _state.update { it.copy(startPoint = coordinates) }
            } catch (error: RouteError) {
                handleCurrentLocationErrors(error)
            }
        }
    }

    private suspend fun handleCurrentLocationErrors(error: RouteError) {
        _events.send(RouteEvent.ShowError(error.toUiError()))

        if (error is RouteError.MissingLocationPermission) {
            _events.send(RouteEvent.RequestLocationPermission)
        }
    }

    private fun addWaypoint(coordinates: Coordinates) {
        _state.update { state ->
            val newWaypoint = RoutePoint(coordinates = coordinates, order = state.waypoints.size)
            state.copy(waypoints = state.waypoints + newWaypoint)
        }
    }

    private fun generateRoute() {
        val state = _state.value
        val startPoint = state.startPoint ?: return

        viewModelScope.launch {
            _state.update { it.copy(isLoading = true) }

            val draftRoute = RouteDraft(
                startPoint = RoutePoint(coordinates = startPoint, order = 0),
                waypoints = state.waypoints
            )

            try {
                val route = generateClosedRouteUseCase(draftRoute)
                _state.update { it.copy(isLoading = false, generatedRoute = route) }
            } catch (error: RouteError) {
                _state.update { it.copy(isLoading = false) }
                _events.send(RouteEvent.ShowError(error.toUiError()))
            }
        }
    }

    private fun reset() {
        _state.update { RouteState() }
        loadCurrentLocation()
        getAndUpdateUserProfile()
    }

    private fun removeWaypoint(removeCandidate: RoutePoint) {
        _state.update { state ->
            val updatedWaypoints = state.waypoints
                .filterNot { it == removeCandidate }
                .mapIndexed { index, point -> point.copy(order = index) }

            state.copy(waypoints = updatedWaypoints, generatedRoute = null)
        }
    }

    private fun saveUserProfile(weightKg: Double) {
        viewModelScope.launch {
            val userProfile = UserProfile(weightKg)
            userProfileRepository.saveUserProfile(userProfile)
            _state.update { state -> state.copy(userProfile = userProfile) }
        }
    }

    private fun startTracking() {
        viewModelScope.launch {
            val profile = userProfileRepository.getUserProfile()
            if (profile == null) {
                _events.send(RouteEvent.RequestUserProfile)
            } else {
                val startPoint = state.value.startPoint
                val plannedRoutePoints = state.value.generatedRoute?.points?.map { it.coordinates }
                if (startPoint != null && !plannedRoutePoints.isNullOrEmpty()) {
                    _events.send(
                        RouteEvent.NavigateToTracking(
                            startPoint = startPoint,
                            plannedRoutePoints = plannedRoutePoints,
                            activityType = state.value.selectedActivityType
                        )
                    )
                }
            }
        }
    }

    private fun getAndUpdateUserProfile() {
        viewModelScope.launch {
            val userProfile = userProfileRepository.getUserProfile()
            _state.update { state -> state.copy(userProfile = userProfile) }
        }
    }
}

data class RouteState(
    val startPoint: Coordinates? = null,
    val waypoints: List<RoutePoint> = emptyList(),
    val generatedRoute: Route? = null,
    val userProfile: UserProfile? = null,
    val selectedActivityType: ActivityType = ActivityType.Running, // by default
    val isLoading: Boolean = false
) {
    val canGenerateRoute: Boolean
        get() = startPoint != null && waypoints.size >= MIN_WAYPOINTS && !isLoading

    private companion object {
        const val MIN_WAYPOINTS = 3
    }
}

sealed interface RouteAction {
    data class MapTapped(val coordinates: Coordinates) : RouteAction
    data class WaypointRemoved(val waypoint: RoutePoint) : RouteAction
    data class ActivityTypeSelected(val activityType: ActivityType) : RouteAction
    data class UserProfileSaved(val weightKg: Double) : RouteAction
    data object GenerateRouteClicked : RouteAction
    data object ResetClicked : RouteAction
    data object StartTrackingClicked : RouteAction
    data object LocationPermissionGranted : RouteAction
}

sealed interface RouteEvent {
    data object RequestLocationPermission : RouteEvent
    data class ShowError(val error: RouteUiError) : RouteEvent
    data object RequestUserProfile : RouteEvent
    data class NavigateToTracking(
        val startPoint: Coordinates,
        val plannedRoutePoints: List<Coordinates>,
        val activityType: ActivityType
    ) : RouteEvent
}
