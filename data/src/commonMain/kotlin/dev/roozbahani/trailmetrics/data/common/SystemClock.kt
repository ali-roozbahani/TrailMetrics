package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlin.time.Clock as KotlinClock

class SystemClock : Clock {
    override fun nowMillis(): Long = KotlinClock.System.now().toEpochMilliseconds()

    // Placeholder so the failing-tests commit compiles; the platform source replaces it next.
    override fun elapsedRealtimeMillis(): Long = TODO("monotonic platform source")
}
