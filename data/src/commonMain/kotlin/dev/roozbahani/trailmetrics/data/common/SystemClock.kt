package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlin.time.Clock as KotlinClock

class SystemClock : Clock {
    override fun nowMillis(): Long = KotlinClock.System.now().toEpochMilliseconds()

    override fun elapsedRealtimeMillis(): Long = platformElapsedRealtimeMillis()
}

/**
 * The platform's monotonic clock that keeps counting while the device sleeps, in milliseconds.
 * Not kotlin.time.TimeSource.Monotonic: on Android that is System.nanoTime, which stops in deep sleep.
 */
internal expect fun platformElapsedRealtimeMillis(): Long
