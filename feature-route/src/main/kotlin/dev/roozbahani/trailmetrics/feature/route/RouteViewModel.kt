package dev.roozbahani.trailmetrics.feature.route

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.RouteUiErrorMapper
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
    private val userProfileRepository: UserProfileRepository,
    private val uiErrorMapper: RouteUiErrorMapper
) : ViewModel() {

    private val _uiState = MutableStateFlow(RouteUiState())
    val uiState: StateFlow<RouteUiState> = _uiState.asStateFlow()

    private val _uiEvents = Channel<RouteUiEvent>(Channel.BUFFERED)
    val uiEvents: Flow<RouteUiEvent> = _uiEvents.receiveAsFlow()

    init {
        loadCurrentLocation()
        getAndUpdateUserProfile()
    }

    private fun loadCurrentLocation() {
        viewModelScope.launch {
            getCurrentLocationUseCase()
                .onSuccess { coordinates ->
                    _uiState.update { it.copy(startPoint = coordinates) }
                }
                .onFailure { throwable ->
                    handleCurrentLocationErrors(throwable as? RouteError)
                }
        }
    }

    private fun handleCurrentLocationErrors(error: RouteError?) {
        viewModelScope.launch {
            _uiEvents.send(RouteUiEvent.ShowError(error = uiErrorMapper.map(error)))

            if (error is RouteError.MissingLocationPermission) {
                _uiEvents.send(RouteUiEvent.RequestLocationPermission)
            }
        }
    }

    fun onLocationPermissionGranted() {
        loadCurrentLocation()
    }

    fun onMapTapped(coordinates: Coordinates) {
        _uiState.update { state ->
            val newWaypoint = RoutePoint(coordinates = coordinates, order = state.waypoints.size)
            state.copy(waypoints = state.waypoints + newWaypoint)
        }
    }

    fun onGenerateRouteClicked() {
        val state = _uiState.value
        val startPoint = state.startPoint ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            val draftRoute = RouteDraft(
                startPoint = RoutePoint(coordinates = startPoint, order = 0),
                waypoints = state.waypoints
            )

            generateClosedRouteUseCase(draftRoute)
                .onSuccess { route ->
                    _uiState.update { it.copy(isLoading = false, generatedRoute = route) }
                }
                .onFailure { error ->
                    _uiState.update { it.copy(isLoading = false) }
                    _uiEvents.send(RouteUiEvent.ShowError(uiErrorMapper.map(error as? RouteError)))
                }
        }
    }

    fun onResetClicked() {
        _uiState.update { RouteUiState() }
        loadCurrentLocation()
    }

    fun onWaypointRemoved(removeCandidate: RoutePoint) {
        _uiState.update { state ->
            val updatedWaypoints = state.waypoints
                .filterNot { it == removeCandidate }
                .mapIndexed { index, point -> point.copy(order = index) }

            state.copy(waypoints = updatedWaypoints, generatedRoute = null)
        }
    }

    fun onActivityTypeSelected(activityType: ActivityType) {
        _uiState.update { state ->
            state.copy(selectedActivityType = activityType)
        }
    }

    fun saveUserProfile(weightKg: Double) {
        viewModelScope.launch {
            val userProfile = UserProfile(weightKg)
            userProfileRepository.saveUserProfile(userProfile)
            _uiState.update { state -> state.copy(userProfile = userProfile) }
        }
    }

    fun onStartTrackingClicked() {
        viewModelScope.launch {
            val profile = userProfileRepository.getUserProfile()
            if (profile == null) {
                _uiEvents.send(RouteUiEvent.RequestUserProfile)
            } else {
                val startPoint = uiState.value.startPoint
                val plannedRoutePoints = uiState.value.generatedRoute?.points?.map { it.coordinates }
                if (startPoint != null && !plannedRoutePoints.isNullOrEmpty()) {
                    _uiEvents.send(
                        RouteUiEvent.NavigateToTracking(
                            startPoint = startPoint,
                            plannedRoutePoints = plannedRoutePoints,
                            activityType = uiState.value.selectedActivityType
                        )
                    )
                }
            }
        }
    }

    private fun getAndUpdateUserProfile() {
        viewModelScope.launch {
            val userProfile = userProfileRepository.getUserProfile()
            _uiState.update { state -> state.copy(userProfile = userProfile) }
        }
    }
}

data class RouteUiState(
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

sealed interface RouteUiEvent {
    data object RequestLocationPermission : RouteUiEvent
    data class ShowError(val error: RouteUiError) : RouteUiEvent
    data object RequestUserProfile : RouteUiEvent
    data class NavigateToTracking(
        val startPoint: Coordinates,
        val plannedRoutePoints: List<Coordinates>,
        val activityType: ActivityType
    ) : RouteUiEvent
}
