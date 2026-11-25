package dev.roozbahani.trailmetrics.core.error

import dev.roozbahani.trailmetrics.domain.model.RouteError

sealed interface RouteUiError {
    data object LocationUnavailable : RouteUiError
    data object MissingLocationPermission : RouteUiError
    data object General : RouteUiError

    /** No response from the network: the screen offers a retry. */
    data object NoConnection : RouteUiError
}

fun RouteError?.toUiError(): RouteUiError = when (this) {
    is RouteError.LocationUnavailable -> RouteUiError.LocationUnavailable
    is RouteError.MissingLocationPermission -> RouteUiError.MissingLocationPermission
    is RouteError.NoConnection -> RouteUiError.NoConnection
    null, is RouteError.InsufficientWaypoints, is RouteError.DirectionsApiError -> RouteUiError.General
}
