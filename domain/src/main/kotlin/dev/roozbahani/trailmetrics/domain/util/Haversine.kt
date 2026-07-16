package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

const val EARTH_RADIUS_METERS = 6371000.0

fun Coordinates.distanceTo(to: Coordinates): Double {
    val lat2Radian = Math.toRadians(to.latitude)
    val lng2Radian = Math.toRadians(to.longitude)
    val lat1Radian = Math.toRadians(this.latitude)
    val lng1Radian = Math.toRadians(this.longitude)

    val deltaLat: Double = lat2Radian - lat1Radian
    val deltaLng: Double = lng2Radian - lng1Radian

    val a: Double = (sin(deltaLat / 2).pow(2)) +
            (cos(lat1Radian) * cos(lat2Radian) * sin(deltaLng / 2).pow(2))
    val c: Double = 2 * atan2(sqrt(a), sqrt(1 - a))
    val distanceMeters = EARTH_RADIUS_METERS * c

    return distanceMeters
}