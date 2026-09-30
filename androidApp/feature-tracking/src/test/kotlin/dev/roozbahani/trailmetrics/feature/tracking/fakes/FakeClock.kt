package dev.roozbahani.trailmetrics.feature.tracking.fakes

import dev.roozbahani.trailmetrics.domain.util.Clock

class FakeClock(var nowMillis: Long = 0L) : Clock {
    override fun nowMillis(): Long = nowMillis
}
