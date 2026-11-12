package dev.roozbahani.trailmetrics.domain.model

data class TrackingMetrics(
    val elapsedMillis: Long,
    val lastUpdateElapsedRealtimeMillis: Long,
    val distanceMeters: Double,
    val path: List<Coordinates>,
    val currentSpeedMetersPerSecond: Float? = null,
    /**
     * True from a Resume until the first location after it. That location is where the user is now,
     * not a step from the last point before the Pause, so it adds to the path but not to
     * [distanceMeters]. Not stored: a stored session comes back Paused and a Resume sets it again.
     */
    val awaitingFirstFixAfterResume: Boolean = false
) {
    val averageSpeedMetersPerSecond: Float?
        get() = if (elapsedMillis > 0) {
            (distanceMeters / (elapsedMillis / 1000.0)).toFloat()
        } else {
            null
        }
}
