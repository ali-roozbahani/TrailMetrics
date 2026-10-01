package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.util.Clock

class FakeClock : Clock {
    private var values: MutableList<Long> = mutableListOf(0L)
    private var elapsedRealtimeValues: MutableList<Long> = mutableListOf(0L)

    fun setValues(vararg newValues: Long) {
        values = newValues.toMutableList()
    }

    fun setElapsedRealtimeValues(vararg newValues: Long) {
        elapsedRealtimeValues = newValues.toMutableList()
    }

    override fun nowMillis(): Long {
        return if (values.size > 1) values.removeAt(0) else values.first()
    }

    override fun elapsedRealtimeMillis(): Long {
        return if (elapsedRealtimeValues.size > 1) elapsedRealtimeValues.removeAt(0) else elapsedRealtimeValues.first()
    }
}
