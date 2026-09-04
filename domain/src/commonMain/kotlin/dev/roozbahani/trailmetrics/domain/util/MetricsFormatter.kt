package dev.roozbahani.trailmetrics.domain.util

import kotlin.math.abs
import kotlin.math.round
import kotlin.math.roundToInt

/**
 * Manual fixed-point formatter for KMP compatibility.
 *
 * kotlin-stdlib-common has no cross-platform equivalent to JVM's
 * String.format("%.2f", ...) (which relies on java.util.Formatter).
 * Rounds before splitting into integer/fraction parts to avoid
 * truncation bugs (e.g. 1.999 -> "2.00", not "1.100").
 */
private fun Double.formatFixed(decimals: Int): String {
    var multiplier = 1.0
    repeat(decimals) { multiplier *= 10 }

    val roundedScaled = round(this * multiplier).toLong()
    val isNegative = roundedScaled < 0
    val absScaled = abs(roundedScaled)

    val divisor = multiplier.toLong()
    val intPart = absScaled / divisor
    val fracPart = absScaled % divisor

    val sign = if (isNegative) "-" else ""
    return if (decimals == 0) {
        "$sign$intPart"
    } else {
        "$sign$intPart.${fracPart.toString().padStart(decimals, '0')}"
    }
}

fun formatDistance(meters: Double): String {
    return if (meters >= 1000) "${(meters / 1000).formatFixed(2)} km" else "${meters.toInt()} m"
}

fun formatElapsedTime(millis: Long): String {
    val totalSeconds = millis / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
}

fun formatSpeed(metersPerSecond: Float?): String {
    if (metersPerSecond == null) return "-- km/h"
    val kmh = metersPerSecond * 3.6
    return "${kmh.formatFixed(1)} km/h"
}

fun formatCalories(calories: Double?): String {
    if (calories == null) return "-- kcal"
    return "${calories.roundToInt()} kcal"
}
