package dev.roozbahani.trailmetrics.data.common

import platform.posix.usleep
import kotlin.test.Test
import kotlin.test.assertTrue

class SystemClockIosTest {

    private val clock = SystemClock()

    @Test
    fun `consecutive elapsedRealtimeMillis reads never decrease`() {
        val first = clock.elapsedRealtimeMillis()
        val second = clock.elapsedRealtimeMillis()

        assertTrue(second >= first, "second read $second is earlier than first $first")
    }

    @Test
    fun `elapsedRealtimeMillis increases after a short delay`() {
        val before = clock.elapsedRealtimeMillis()

        usleep(SLEEP_MICROS)

        val after = clock.elapsedRealtimeMillis()
        assertTrue(after > before, "no advance over a 20 ms sleep: $before -> $after")
    }

    private companion object {
        const val SLEEP_MICROS = 20_000u
    }
}
