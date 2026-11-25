package dev.roozbahani.trailmetrics.domain.model

sealed class RouteError: Throwable() {
    data class InsufficientWaypoints(val required: Int, val actual: Int): RouteError()
    data class DirectionsApiError(val apiException: Throwable): RouteError()

    /**
     * The directions call got no response after its retries: no network, a server that cannot be reached, or a
     * timeout. The user can retry once connected. [networkException] stays a property, not the cause, because
     * an engine's message can hold the request URL (the API key and the route's coordinates).
     */
    data class NoConnection(val networkException: Throwable): RouteError()
    data class LocationUnavailable(val ex: Throwable? = null): RouteError()
    class MissingLocationPermission : RouteError()
}
