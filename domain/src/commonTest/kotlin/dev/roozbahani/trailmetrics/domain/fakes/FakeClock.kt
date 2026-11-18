package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.util.Clock

/**
 * Two independent scripted clocks. Each read returns the next value in its sequence, then keeps
 * returning the last one. Both default to 0.
 */
class FakeClock : Clock {
    private val wallClockValues: MutableList<Long> = mutableListOf(0L)
    private val elapsedRealtimeValues: MutableList<Long> = mutableListOf(0L)

    fun setWallClockValues(vararg newValues: Long) {
        wallClockValues.clear()
        wallClockValues.addAll(newValues.toList())
    }

    fun setElapsedRealtimeValues(vararg newValues: Long) {
        elapsedRealtimeValues.clear()
        elapsedRealtimeValues.addAll(newValues.toList())
    }

    override fun nowMillis(): Long = wallClockValues.next()

    override fun elapsedRealtimeMillis(): Long = elapsedRealtimeValues.next()

    private fun MutableList<Long>.next(): Long = if (size > 1) removeAt(0) else first()
}
