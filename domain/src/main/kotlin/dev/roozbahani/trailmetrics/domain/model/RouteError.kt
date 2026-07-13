package dev.roozbahani.trailmetrics.domain.model

sealed class RouteError: Throwable() {
    data class InsufficientWaypoints(val required: Int, val actual: Int): RouteError()
    data class DirectionsApiError(val apiException: Throwable): RouteError()
    data class LocationUnavailable(val ex: Throwable? = null): RouteError()
    class MissingLocationPermission : RouteError()
}
