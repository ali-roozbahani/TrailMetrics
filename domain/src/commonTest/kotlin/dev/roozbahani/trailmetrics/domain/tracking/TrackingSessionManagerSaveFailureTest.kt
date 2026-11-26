package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.fakes.FakeClock
import dev.roozbahani.trailmetrics.domain.fakes.FakeLocationRepository
import dev.roozbahani.trailmetrics.domain.fakes.FakeLogger
import dev.roozbahani.trailmetrics.domain.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.fakes.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * [TrackingSessionManager.unsavedSessionWarning]: a failing save of the in-progress session is surfaced once
 * per session, not on every write (owner decision of 2026-11-25).
 */
class TrackingSessionManagerSaveFailureTest {

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.327, 12.394)
    private val point3 = Coordinates(51.318, 12.400)
    private val testScheduler = TestCoroutineScheduler()
    private val testScope = TestScope(StandardTestDispatcher(testScheduler))
    private val store = FakeTrackingSessionStore()
    private val locationRepository = FakeLocationRepository()
    private val updates = MutableSharedFlow<LocationUpdate>()
    private val manager = TrackingSessionManager(
        locationRepository = locationRepository,
        updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
        trackingServiceLauncher = FakeTrackingServiceLauncher(),
        speedCalculator = SpeedCalculator(),
        clock = FakeClock().also { it.setElapsedRealtimeValues(0L, 1_000L, 2_000L, 3_000L, 4_000L, 5_000L) },
        logger = FakeLogger(),
        trackingSessionStore = store,
        scope = testScope
    )

    @Test
    fun `a session whose saves succeed raises no warning`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)

        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()
        emitFix(point2)
        manager.stop()
        testScheduler.runCurrent()

        assertFalse(manager.unsavedSessionWarning.isRaised.value)
    }

    @Test
    fun `the first failed save raises the warning and tracking goes on`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        store.saveFailure = IllegalStateException("disk full")

        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()

        assertTrue(manager.unsavedSessionWarning.isRaised.value)
        emitFix(point2)
        assertEquals(listOf(point1, point2), assertIs<TrackingState.Tracking>(manager.currentState.value).metrics.path)
    }

    @Test
    fun `once shown the warning is not raised again by later failed saves of the same session`() =
        runTest(testScheduler) {
            locationRepository.setUpdatesFlow(updates)
            store.saveFailure = IllegalStateException("disk full")
            manager.start(point1, ActivityType.Running)
            testScheduler.runCurrent()

            manager.unsavedSessionWarning.markShown()
            emitFix(point2)
            emitFix(point3)
            manager.pause()
            testScheduler.runCurrent()

            assertFalse(manager.unsavedSessionWarning.isRaised.value)
        }

    @Test
    fun `a new session raises the warning again on its own first failed save`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        store.saveFailure = IllegalStateException("disk full")
        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()
        manager.unsavedSessionWarning.markShown()
        manager.stop()
        testScheduler.runCurrent()
        store.saveFailure = null
        manager.clearSession()
        testScheduler.runCurrent()

        store.saveFailure = IllegalStateException("disk full again")
        manager.start(point2, ActivityType.Cycling)
        testScheduler.runCurrent()

        assertTrue(manager.unsavedSessionWarning.isRaised.value)
    }

    @Test
    fun `a new session clears a warning of the previous one that no screen showed`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        store.saveFailure = IllegalStateException("disk full")
        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()
        manager.stop()
        testScheduler.runCurrent()
        store.saveFailure = null
        manager.clearSession()
        testScheduler.runCurrent()

        manager.start(point2, ActivityType.Running)
        testScheduler.runCurrent()

        assertFalse(manager.unsavedSessionWarning.isRaised.value)
    }

    @Test
    fun `stop clears a warning that no screen has shown yet`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        store.saveFailure = IllegalStateException("disk full")
        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()
        assertTrue(manager.unsavedSessionWarning.isRaised.value)

        manager.stop()
        testScheduler.runCurrent()

        assertFalse(manager.unsavedSessionWarning.isRaised.value)
    }

    @Test
    fun `a failed save of the stopped session raises no warning`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()

        store.saveFailure = IllegalStateException("disk full")
        manager.stop()
        testScheduler.runCurrent()

        assertIs<TrackingState.Finished>(manager.currentState.value)
        assertFalse(manager.unsavedSessionWarning.isRaised.value)
    }

    @Test
    fun `discarding a running session clears its warning`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        store.saveFailure = IllegalStateException("disk full")
        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()

        manager.discard()
        testScheduler.runCurrent()

        assertFalse(manager.unsavedSessionWarning.isRaised.value)
    }

    @Test
    fun `clearing a restored finished session clears its warning`() = runTest(testScheduler) {
        val metrics = TrackingMetrics(
            elapsedMillis = 5_000L,
            lastUpdateElapsedRealtimeMillis = 9_000L,
            distanceMeters = 42.0,
            path = listOf(point1, point2),
            currentSpeedMetersPerSecond = 1.5f
        )
        store.stored = TrackingState.Finished(metrics)
        store.saveFailure = IllegalStateException("disk full")
        manager.restore()
        testScheduler.runCurrent()
        assertTrue(manager.unsavedSessionWarning.isRaised.value, "precondition: the restored session's save failed")

        manager.clearSession()
        testScheduler.runCurrent()

        assertFalse(manager.unsavedSessionWarning.isRaised.value)
    }

    private suspend fun emitFix(coordinates: Coordinates) {
        updates.emit(LocationUpdate.Success(coordinates, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.advanceUntilIdle()
    }
}
