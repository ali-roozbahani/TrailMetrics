package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

const val EARTH_RADIUS_METERS = 6371000.0

private fun Double.toRadians(): Double = this * PI / 180.0

fun Coordinates.distanceTo(to: Coordinates): Double {
    val lat2Radian = to.latitude.toRadians()
    val lng2Radian = to.longitude.toRadians()
    val lat1Radian = this.latitude.toRadians()
    val lng1Radian = this.longitude.toRadians()

    val deltaLat: Double = lat2Radian - lat1Radian
    val deltaLng: Double = lng2Radian - lng1Radian

    val a: Double = (sin(deltaLat / 2).pow(2)) +
            (cos(lat1Radian) * cos(lat2Radian) * sin(deltaLng / 2).pow(2))
    val c: Double = 2 * atan2(sqrt(a), sqrt(1 - a))
    val distanceMeters = EARTH_RADIUS_METERS * c

    return distanceMeters
}
