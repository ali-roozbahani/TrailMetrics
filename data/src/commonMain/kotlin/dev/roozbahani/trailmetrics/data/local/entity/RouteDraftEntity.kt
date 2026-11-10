package dev.roozbahani.trailmetrics.data.local.entity

import androidx.room3.Entity
import androidx.room3.PrimaryKey
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates

/**
 * The one route being planned: always the row with [ROUTE_DRAFT_ID]. The start point is null when both
 * of its columns are; the generated route is null when [generatedRoutePoints] is.
 */
@Entity(tableName = "tbl_route_draft")
data class RouteDraftEntity(
    @PrimaryKey val id: Int = ROUTE_DRAFT_ID,
    val startLatitude: Double?,
    val startLongitude: Double?,
    /** The waypoints in order. */
    val waypoints: List<Coordinates>,
    /** The generated route's points in order; null when no route was generated. */
    val generatedRoutePoints: List<Coordinates>?,
    val generatedRouteDistanceMeters: Double?,
    val activityType: ActivityType
) {
    companion object {
        const val ROUTE_DRAFT_ID = 1
    }
}
