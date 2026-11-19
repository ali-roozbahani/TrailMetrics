package dev.roozbahani.trailmetrics.data.tracking

import dev.roozbahani.trailmetrics.domain.tracking.BackgroundLocationUpdates
import kotlin.test.Test
import kotlin.test.assertEquals

private class FakeBackgroundLocationUpdates : BackgroundLocationUpdates {
    val calls = mutableListOf<Boolean>()

    override fun setEnabled(enabled: Boolean) {
        calls += enabled
    }
}

class IosTrackingServiceLauncherTest {
    private val backgroundUpdates = FakeBackgroundLocationUpdates()
    private val launcher = IosTrackingServiceLauncher(backgroundUpdates)

    @Test
    fun `nothing is switched before tracking starts`() {
        assertEquals(emptyList(), backgroundUpdates.calls)
    }

    @Test
    fun `start switches background updates on`() {
        launcher.start()

        assertEquals(listOf(true), backgroundUpdates.calls)
    }

    @Test
    fun `stop switches background updates off`() {
        launcher.start()
        launcher.stop()

        assertEquals(listOf(true, false), backgroundUpdates.calls)
    }
}
