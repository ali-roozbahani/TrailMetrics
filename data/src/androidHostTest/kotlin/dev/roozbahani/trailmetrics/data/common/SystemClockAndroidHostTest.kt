package dev.roozbahani.trailmetrics.data.common

import android.os.SystemClock as AndroidSystemClock
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration
import kotlin.test.assertEquals

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SystemClockAndroidHostTest {

    private val clock = SystemClock()

    @Test
    fun `elapsedRealtimeMillis advances with the Android SystemClock`() {
        val before = clock.elapsedRealtimeMillis()

        ShadowSystemClock.advanceBy(Duration.ofSeconds(90))

        assertEquals(90_000L, clock.elapsedRealtimeMillis() - before)
    }

    @Test
    fun `elapsedRealtimeMillis keeps counting through deep sleep`() {
        val before = clock.elapsedRealtimeMillis()
        val uptimeBefore = AndroidSystemClock.uptimeMillis()

        ShadowSystemClock.simulateDeepSleep(Duration.ofMinutes(3))

        assertEquals(180_000L, clock.elapsedRealtimeMillis() - before)
        // uptimeMillis stops while asleep: the clock we read is not that one.
        assertEquals(uptimeBefore, AndroidSystemClock.uptimeMillis())
    }
}
