package dev.roozbahani.trailmetrics.feature.route

import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RoutePoint

/**
 * Whether the camera fits the whole plan. [planAlreadySeen] is true once non-empty [waypoints] have been
 * handled. A restored plan arrives with two or more waypoints as its first non-empty ones: fit it once.
 * Waypoints the user taps arrive one at a time, so the camera stays where the user moved it.
 */
fun isPlanFitNeeded(waypoints: List<RoutePoint>, planAlreadySeen: Boolean): Boolean =
    !planAlreadySeen && waypoints.size >= MIN_WAYPOINTS_TO_FIT

/** The smallest bounds that hold every point of a plan (at least one point). */
internal fun planBounds(points: List<Coordinates>): LatLngBounds =
    LatLngBounds.builder().apply { points.forEach { include(LatLng(it.latitude, it.longitude)) } }.build()

private const val MIN_WAYPOINTS_TO_FIT = 2
