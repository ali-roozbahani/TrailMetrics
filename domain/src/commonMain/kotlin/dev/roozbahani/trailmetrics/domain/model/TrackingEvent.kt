package dev.roozbahani.trailmetrics.domain.model

sealed interface TrackingEvent {
    data class Start(val startPoint: Coordinates, val elapsedRealtimeMillis: Long) : TrackingEvent
    data class Pause(val elapsedRealtimeMillis: Long) : TrackingEvent
    data class Resume(val elapsedRealtimeMillis: Long) : TrackingEvent
    data class Stop(val elapsedRealtimeMillis: Long) : TrackingEvent
    data class LocationReceived(
        val coordinates: Coordinates,
        val elapsedRealtimeMillis: Long,
        val speedMetersPerSecond: Float?
    ) : TrackingEvent
}
