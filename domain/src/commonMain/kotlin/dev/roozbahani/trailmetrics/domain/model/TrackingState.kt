package dev.roozbahani.trailmetrics.domain.model

sealed interface TrackingState {
    data object Idle : TrackingState
    data class Tracking(val metrics: TrackingMetrics) : TrackingState
    data class Paused(val metrics: TrackingMetrics) : TrackingState
    data class Finished(val metrics: TrackingMetrics) : TrackingState
}

/**
 * The only way the domain makes a [TrackingState.Paused]: a paused session records nothing, so the speed of its
 * last fix is not a current speed and is not kept (both apps show the state's metrics as they are). A Resume
 * shows no speed until its first fix.
 */
internal fun pausedState(metrics: TrackingMetrics): TrackingState.Paused =
    TrackingState.Paused(metrics.copy(currentSpeedMetersPerSecond = null))
