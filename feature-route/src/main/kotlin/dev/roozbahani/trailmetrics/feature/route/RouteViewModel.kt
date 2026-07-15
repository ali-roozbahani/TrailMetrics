package dev.roozbahani.trailmetrics.feature.route

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteDraft
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
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
    private val uiErrorMapper: RouteUiErrorMapper
) : ViewModel() {

    private val _uiState = MutableStateFlow(RouteUiState())
    val uiState: StateFlow<RouteUiState> = _uiState.asStateFlow()

    private val _uiEvents = Channel<RouteUiEvent>(Channel.BUFFERED)
    val uiEvents: Flow<RouteUiEvent> = _uiEvents.receiveAsFlow()

    init {
        loadCurrentLocation()
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
            _uiEvents.send(RouteUiEvent.ShowError(error = uiErrorMapper.mapError(error)))

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
                    _uiEvents.send(RouteUiEvent.ShowError(uiErrorMapper.mapError(error as? RouteError)))
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
}

data class RouteUiState(
    val startPoint: Coordinates? = null,
    val waypoints: List<RoutePoint> = emptyList(),
    val generatedRoute: Route? = null,
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
}

data class RouteUiError(@param:StringRes val errorResId: Int)

class RouteUiErrorMapper {
    fun mapError(error: RouteError?): RouteUiError {
        return when (error) {
            is RouteError.LocationUnavailable -> {
                RouteUiError(R.string.msg_route_ui_error_location_unavailable)
            }

            is RouteError.MissingLocationPermission -> {
                RouteUiError(R.string.msg_route_ui_error_missing_location_permission)
            }

            else -> {
                RouteUiError(R.string.msg_route_ui_error_general)
            }
        }
    }
}