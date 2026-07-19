package dev.roozbahani.trailmetrics.domain.util

fun formatDistance(meters: Double): String {
    return if (meters >= 1000) "%.2f km".format(meters / 1000) else "${meters.toInt()} m"
}

fun formatElapsedTime(millis: Long): String {
    val totalSeconds = millis / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%02d:%02d".format(minutes, seconds)
}
