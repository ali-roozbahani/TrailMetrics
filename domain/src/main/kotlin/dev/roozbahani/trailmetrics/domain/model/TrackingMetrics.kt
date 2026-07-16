package dev.roozbahani.trailmetrics.domain.model

data class TrackingMetrics(
    val elapsedMillis: Long,
    val lastUpdateTimestampMillis: Long,
    val distanceMeters: Double,
    val path: List<Coordinates>
)
