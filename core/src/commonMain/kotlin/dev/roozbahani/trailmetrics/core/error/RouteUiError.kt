package dev.roozbahani.trailmetrics.core.error

import dev.roozbahani.trailmetrics.domain.model.RouteError

sealed interface RouteUiError {
    data object LocationUnavailable : RouteUiError
    data object MissingLocationPermission : RouteUiError
    data object General : RouteUiError
}

fun RouteError?.toUiError(): RouteUiError = when (this) {
    is RouteError.LocationUnavailable -> RouteUiError.LocationUnavailable
    is RouteError.MissingLocationPermission -> RouteUiError.MissingLocationPermission
    else -> RouteUiError.General
}
