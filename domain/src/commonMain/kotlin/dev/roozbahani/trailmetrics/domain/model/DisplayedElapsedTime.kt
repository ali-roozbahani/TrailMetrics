package dev.roozbahani.trailmetrics.domain.model

/**
 * The elapsed time a screen shows at [nowElapsedRealtimeMillis], for both platforms. Display only: the
 * accounting of [TrackingMetrics.elapsedMillis] (`UpdateTrackingStateUseCase`, which adds time on location
 * events, a Pause and a Stop) is unchanged and nothing here is stored.
 *
 * While [TrackingState.Tracking], the time since the last accounted update is added, so the display ticks
 * without location events and equals what the next location event will account (no jump when it arrives).
 * Both add [millisSinceLastUpdate], so they cannot differ. A Resume sets
 * [TrackingMetrics.lastUpdateElapsedRealtimeMillis] to the resume time, so the pause is not counted.
 * [TrackingState.Paused] and [TrackingState.Finished] show the accounted time, [TrackingState.Idle] 0.
 *
 * [nowElapsedRealtimeMillis] is `Clock.elapsedRealtimeMillis()`, the monotonic timebase of
 * [TrackingMetrics.lastUpdateElapsedRealtimeMillis]; never `Clock.nowMillis()`.
 */
fun TrackingState.displayedElapsedMillis(nowElapsedRealtimeMillis: Long): Long = when (this) {
    TrackingState.Idle -> 0L
    is TrackingState.Tracking -> metrics.elapsedMillis + metrics.millisSinceLastUpdate(nowElapsedRealtimeMillis)
    is TrackingState.Paused -> metrics.elapsedMillis
    is TrackingState.Finished -> metrics.elapsedMillis
}

/**
 * The recorded time from the last accounted update (a fix, a Start or a Resume) to [elapsedRealtimeMillis]: what a
 * location event, a Pause or a Stop adds (`UpdateTrackingStateUseCase`), and what the display adds while Tracking
 * ([displayedElapsedMillis]). The contract is monotonic input (`Clock.elapsedRealtimeMillis`), so this is never
 * negative in practice; the clamp keeps these pure functions safe for any caller.
 */
internal fun TrackingMetrics.millisSinceLastUpdate(elapsedRealtimeMillis: Long): Long =
    (elapsedRealtimeMillis - lastUpdateElapsedRealtimeMillis).coerceAtLeast(0L)
