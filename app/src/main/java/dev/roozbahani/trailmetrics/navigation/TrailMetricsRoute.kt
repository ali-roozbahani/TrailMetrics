package dev.roozbahani.trailmetrics.navigation

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.serialization.Serializable

sealed interface TrailMetricsRoute {
    @Serializable
    data object RoutePlanning : TrailMetricsRoute

    @Serializable
    data class Tracking(
        val startPoint: Coordinates,
        val plannedRoutePoints: List<Coordinates>,
        val selectedActivityType: ActivityType
    ) : TrailMetricsRoute

    @Serializable
    data object History : TrailMetricsRoute

    @Serializable
    data class ActivityDetails(val activityId: Long) : TrailMetricsRoute
}
