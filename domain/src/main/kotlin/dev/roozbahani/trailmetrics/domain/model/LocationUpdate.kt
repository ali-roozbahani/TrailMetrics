package dev.roozbahani.trailmetrics.domain.model

sealed interface LocationUpdate {
    data class Success(val coordinates: Coordinates) : LocationUpdate
    data class Unavailable(val reason: RouteError) : LocationUpdate
}
