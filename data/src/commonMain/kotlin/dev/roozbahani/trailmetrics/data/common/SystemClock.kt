package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlin.time.Clock as KotlinClock

class SystemClock : Clock {
    override fun nowMillis(): Long = KotlinClock.System.now().toEpochMilliseconds()
}
