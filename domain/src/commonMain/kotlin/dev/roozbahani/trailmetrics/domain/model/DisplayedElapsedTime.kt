package dev.roozbahani.trailmetrics.domain.model

/**
 * The elapsed time a screen shows at [nowElapsedRealtimeMillis], for both platforms. Display only: the
 * accounting of [TrackingMetrics.elapsedMillis] (`UpdateTrackingStateUseCase`, which adds time on location
 * events, a Pause and a Stop) is unchanged and nothing here is stored.
 *
 * While [TrackingState.Tracking], the time since the last accounted update is added, so the display ticks
 * without location events and equals what the next location event will account (no jump when it arrives).
 * The difference is clamped at 0, as in `UpdateTrackingStateUseCase`. A Resume sets
 * [TrackingMetrics.lastUpdateElapsedRealtimeMillis] to the resume time, so the pause is not counted.
 * [TrackingState.Paused] and [TrackingState.Finished] show the accounted time, [TrackingState.Idle] 0.
 *
 * [nowElapsedRealtimeMillis] is `Clock.elapsedRealtimeMillis()`, the monotonic timebase of
 * [TrackingMetrics.lastUpdateElapsedRealtimeMillis]; never `Clock.nowMillis()`.
 */
fun TrackingState.displayedElapsedMillis(nowElapsedRealtimeMillis: Long): Long = when (this) {
    TrackingState.Idle -> 0L
    is TrackingState.Tracking -> metrics.elapsedMillis +
        (nowElapsedRealtimeMillis - metrics.lastUpdateElapsedRealtimeMillis).coerceAtLeast(0L)
    is TrackingState.Paused -> metrics.elapsedMillis
    is TrackingState.Finished -> metrics.elapsedMillis
}
