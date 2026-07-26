package dev.roozbahani.trailmetrics.domain.util

import kotlin.math.roundToInt

fun formatDistance(meters: Double): String {
    return if (meters >= 1000) "%.2f km".format(meters / 1000) else "${meters.toInt()} m"
}

fun formatElapsedTime(millis: Long): String {
    val totalSeconds = millis / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%02d:%02d".format(minutes, seconds)
}

fun formatSpeed(metersPerSecond: Float?): String {
    if (metersPerSecond == null) return "-- km/h"
    val kmh = metersPerSecond * 3.6f
    return "%.1f km/h".format(kmh)
}

fun formatCalories(calories: Double?): String {
    if (calories == null) return "-- kcal"
    return "${calories.roundToInt()} kcal"
}
