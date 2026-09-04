package dev.roozbahani.trailmetrics.domain.model

sealed interface LocationUpdate {
    data class Success(
        val coordinates: Coordinates,
        val speedMetersPerSecond: Float?,
        val accuracyMeters: Float?
    ) : LocationUpdate
    data class Unavailable(val reason: RouteError) : LocationUpdate
}
