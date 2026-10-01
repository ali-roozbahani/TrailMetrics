package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.util.Clock

/**
 * Two independent scripted clocks. Each read returns the next value in its sequence, then keeps
 * returning the last one. Both default to 0.
 */
class FakeClock : Clock {
    private var wallClockValues: MutableList<Long> = mutableListOf(0L)
    private var elapsedRealtimeValues: MutableList<Long> = mutableListOf(0L)

    fun setWallClockValues(vararg newValues: Long) {
        wallClockValues = newValues.toMutableList()
    }

    fun setElapsedRealtimeValues(vararg newValues: Long) {
        elapsedRealtimeValues = newValues.toMutableList()
    }

    override fun nowMillis(): Long = wallClockValues.next()

    override fun elapsedRealtimeMillis(): Long = elapsedRealtimeValues.next()

    private fun MutableList<Long>.next(): Long = if (size > 1) removeAt(0) else first()
}
