package dev.roozbahani.trailmetrics.domain.model

sealed interface TrackingState {
    data object Idle : TrackingState
    data class Tracking(val metrics: TrackingMetrics) : TrackingState
    data class Paused(val metrics: TrackingMetrics) : TrackingState
    data class Finished(val metrics: TrackingMetrics) : TrackingState
}
