package dev.roozbahani.trailmetrics

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.serialization.Serializable

sealed interface TrailMetricsRoute {
    @Serializable
    data object RoutePlanning : TrailMetricsRoute

    @Serializable
    data class Tracking(val startPoint: Coordinates) : TrailMetricsRoute
}
