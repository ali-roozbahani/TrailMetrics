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

/**
 * The only way the domain makes a [TrackingState.Finished]: a finished session records nothing, so the speed of its
 * last fix is not a current speed and is not kept, as for [pausedState] (both apps show the finished session's
 * metrics as they are).
 */
internal fun finishedState(metrics: TrackingMetrics): TrackingState.Finished =
    TrackingState.Finished(metrics.copy(currentSpeedMetersPerSecond = null))
