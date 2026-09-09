package dev.roozbahani.trailmetrics.core.navigation

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.serialization.Serializable

sealed interface AppRoute {
    @Serializable
    data object RoutePlanning : AppRoute

    @Serializable
    data class Tracking(
        val startPoint: Coordinates,
        val plannedRoutePoints: List<Coordinates>,
        val selectedActivityType: ActivityType
    ) : AppRoute

    @Serializable
    data object History : AppRoute

    @Serializable
    data class ActivityDetails(val activityId: Long) : AppRoute
}
