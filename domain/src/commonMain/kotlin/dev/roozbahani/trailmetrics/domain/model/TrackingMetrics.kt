package dev.roozbahani.trailmetrics.domain.model

data class TrackingMetrics(
    val elapsedMillis: Long,
    val lastUpdateTimestampMillis: Long,
    val distanceMeters: Double,
    val path: List<Coordinates>,
    val currentSpeedMetersPerSecond: Float? = null
) {
    val averageSpeedMetersPerSecond: Float?
        get() = if (elapsedMillis > 0) {
            (distanceMeters / (elapsedMillis / 1000.0)).toFloat()
        } else {
            null
        }
}
