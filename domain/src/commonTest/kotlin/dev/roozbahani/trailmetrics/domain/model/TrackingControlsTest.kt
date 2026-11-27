package dev.roozbahani.trailmetrics.domain.model

import kotlin.test.Test
import kotlin.test.assertEquals

/** Every [TrackingState] against every control, with and without the stored session still being read. */
class TrackingControlsTest {

    private val metrics = TrackingMetrics(
        elapsedMillis = 60_000L,
        lastUpdateElapsedRealtimeMillis = 60_000L,
        distanceMeters = 100.0,
        path = listOf(Coordinates(1.0, 1.0), Coordinates(1.1, 1.1))
    )

    private val idle = TrackingState.Idle
    private val tracking = TrackingState.Tracking(metrics)
    private val paused = TrackingState.Paused(metrics)
    private val finished = TrackingState.Finished(metrics)

    private fun controls(
        canStart: Boolean = false,
        canPause: Boolean = false,
        canResume: Boolean = false,
        canStop: Boolean = false,
        canSave: Boolean = false,
        canDiscard: Boolean = false
    ) = TrackingControls(canStart, canPause, canResume, canStop, canSave, canDiscard)

    @Test
    fun `idle offers only Start`() {
        assertEquals(controls(canStart = true), idle.availableControls(isRestoring = false))
    }

    @Test
    fun `tracking offers Pause and Stop`() {
        assertEquals(controls(canPause = true, canStop = true), tracking.availableControls(isRestoring = false))
    }

    @Test
    fun `paused offers Resume and Stop`() {
        assertEquals(controls(canResume = true, canStop = true), paused.availableControls(isRestoring = false))
    }

    @Test
    fun `a finished session offers only Save and Discard and never Start`() {
        assertEquals(controls(canSave = true, canDiscard = true), finished.availableControls(isRestoring = false))
    }

    @Test
    fun `while the stored session is read nothing is offered in idle`() {
        assertEquals(controls(), idle.availableControls(isRestoring = true))
    }

    @Test
    fun `while the stored session is read the other states are offered as when it is not`() {
        listOf(tracking, paused, finished).forEach { state ->
            assertEquals(
                state.availableControls(isRestoring = false),
                state.availableControls(isRestoring = true),
                "for $state"
            )
        }
    }

    @Test
    fun `Start is offered in no state but idle`() {
        listOf(tracking, paused, finished).forEach { state ->
            assertEquals(false, state.availableControls(isRestoring = false).canStart, "for $state")
        }
    }

    @Test
    fun `Stop is available exactly when Pause or Resume is`() {
        listOf(idle, tracking, paused, finished).forEach { state ->
            val controls = state.availableControls(isRestoring = false)
            assertEquals(controls.canPause || controls.canResume, controls.canStop, "for $state")
        }
    }

    @Test
    fun `Discard is offered in no state but finished`() {
        listOf(idle, tracking, paused).forEach { state ->
            assertEquals(false, state.availableControls(isRestoring = false).canDiscard, "for $state")
            assertEquals(false, state.availableControls(isRestoring = true).canDiscard, "for $state")
        }
        assertEquals(true, finished.availableControls(isRestoring = true).canDiscard)
    }
}
