package dev.roozbahani.trailmetrics.domain.model

sealed interface TrackingEvent {
    data class Start(val startPoint: Coordinates, val timestampMillis: Long) : TrackingEvent
    data class Pause(val timestampMillis: Long) : TrackingEvent
    data class Resume(val timestampMillis: Long) : TrackingEvent
    data class Stop(val timestampMillis: Long) : TrackingEvent
    data class LocationReceived(val coordinates: Coordinates, val timestampMillis: Long) : TrackingEvent
}
