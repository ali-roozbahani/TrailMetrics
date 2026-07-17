package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.Clock

class SystemClock : Clock {
    override fun nowMillis(): Long {
        return System.currentTimeMillis()
    }
}
