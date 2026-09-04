package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.util.Clock

class FakeClock : Clock {
    private var values: MutableList<Long> = mutableListOf(0L)

    fun setValues(vararg newValues: Long) {
        values = newValues.toMutableList()
    }

    override fun nowMillis(): Long {
        return if (values.size > 1) values.removeAt(0) else values.first()
    }
}
