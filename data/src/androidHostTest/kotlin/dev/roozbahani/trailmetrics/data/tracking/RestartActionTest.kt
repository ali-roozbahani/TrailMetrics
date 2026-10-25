package dev.roozbahani.trailmetrics.data.tracking

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class RestartActionTest {

    private fun metrics(distanceMeters: Double) = TrackingMetrics(
        elapsedMillis = 60_000L,
        lastUpdateElapsedRealtimeMillis = 60_000L,
        distanceMeters = distanceMeters,
        path = listOf(Coordinates(51.336, 12.388))
    )

    @Test
    fun `no stored session stops silently`() {
        assertEquals(RestartAction.StopSilently, restartActionFor(TrackingState.Idle))
    }

    @Test
    fun `a paused session shows the distance in meters and offers to continue`() {
        val action = restartActionFor(TrackingState.Paused(metrics(850.4)))

        assertEquals(RestartAction.ShowNotice("Paused - 850 m, tap to continue"), action)
    }

    @Test
    fun `a paused session over a kilometer shows kilometers`() {
        val action = restartActionFor(TrackingState.Paused(metrics(1234.0)))

        assertEquals(RestartAction.ShowNotice("Paused - 1.23 km, tap to continue"), action)
    }

    @Test
    fun `a finished session says it is not saved and offers to save`() {
        val action = restartActionFor(TrackingState.Finished(metrics(5000.0)))

        assertEquals(RestartAction.ShowNotice("Finished - not saved, tap to save"), action)
    }

    @Test
    fun `a session that is live in the process keeps the service`() {
        assertEquals(RestartAction.KeepTracking, restartActionFor(TrackingState.Tracking(metrics(10.0))))
    }

    private class RecordingEffects : RestartEffects {
        val calls = mutableListOf<String>()

        override fun stopService() {
            calls += "stop"
        }

        override fun leaveNotice(text: String) {
            calls += "notice: $text"
        }

        override suspend fun keepTracking() {
            calls += "keep"
        }
    }

    private class RecordingLogger : Logger {
        val messages = mutableListOf<String>()

        override fun debug(tag: String, message: String) {
            messages += message
        }
    }

    @Test
    fun `an empty restore stops the service`() = runTest {
        val effects = RecordingEffects()

        handleRestart({ TrackingState.Idle }, RecordingLogger(), effects)

        assertEquals(listOf("stop"), effects.calls)
    }

    @Test
    fun `a paused restore leaves the one notice and nothing else`() = runTest {
        val effects = RecordingEffects()

        handleRestart({ TrackingState.Paused(metrics(850.0)) }, RecordingLogger(), effects)

        assertEquals(listOf("notice: Paused - 850 m, tap to continue"), effects.calls)
    }

    @Test
    fun `a live restore keeps tracking`() = runTest {
        val effects = RecordingEffects()

        handleRestart({ TrackingState.Tracking(metrics(10.0)) }, RecordingLogger(), effects)

        assertEquals(listOf("keep"), effects.calls)
    }

    @Test
    fun `a restore that throws is logged and stops the service`() = runTest {
        val effects = RecordingEffects()
        val logger = RecordingLogger()

        handleRestart({ error("unreadable") }, logger, effects)

        assertEquals(listOf("stop"), effects.calls)
        assertTrue(logger.messages.any { "unreadable" in it })
    }

    @Test
    fun `a cancelled restore is not turned into a stop`() = runTest {
        val effects = RecordingEffects()

        assertFailsWith<CancellationException> {
            handleRestart({ throw CancellationException("cancelled") }, RecordingLogger(), effects)
        }
        assertEquals(emptyList(), effects.calls)
    }
}
