package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.fakes.FakeClock
import dev.roozbahani.trailmetrics.domain.fakes.FakeLocationRepository
import dev.roozbahani.trailmetrics.domain.fakes.FakeLogger
import dev.roozbahani.trailmetrics.domain.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.fakes.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

/** What [TrackingSessionManager] writes to its [TrackingSessionStore], and what restore reads back. */
class TrackingSessionManagerPersistenceTest {

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.327, 12.394)
    private val testScheduler = TestCoroutineScheduler()
    private val testScope = TestScope(StandardTestDispatcher(testScheduler))
    private val store = FakeTrackingSessionStore()
    private val logger = FakeLogger()
    private val locationRepository = FakeLocationRepository()
    private val launcher = FakeTrackingServiceLauncher()
    private val updates = MutableSharedFlow<LocationUpdate>()
    private val manager = newManager()

    private fun newManager(
        locationRepository: FakeLocationRepository = this.locationRepository,
        launcher: FakeTrackingServiceLauncher = this.launcher
    ) = TrackingSessionManager(
        locationRepository = locationRepository,
        updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
        trackingServiceLauncher = launcher,
        speedCalculator = SpeedCalculator(),
        clock = FakeClock().also { it.setElapsedRealtimeValues(0L, 1_000L, 2_000L, 3_000L, 4_000L) },
        logger = logger,
        trackingSessionStore = store,
        scope = testScope
    )

    @Test
    fun `every state the manager moves to is saved in order`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        val seen = mutableListOf<TrackingState>()

        manager.start(point1)
        testScheduler.runCurrent()
        seen += manager.currentState.value
        emitFix(point2)
        seen += manager.currentState.value
        manager.pause()
        testScheduler.runCurrent()
        seen += manager.currentState.value
        manager.resume()
        testScheduler.runCurrent()
        seen += manager.currentState.value
        manager.stop()
        testScheduler.runCurrent()
        seen += manager.currentState.value

        assertEquals(seen, store.savedStates)
        assertIs<TrackingState.Finished>(store.savedStates.last())
    }

    @Test
    fun `Idle is never saved`() = runTest(testScheduler) {
        testScheduler.runCurrent()

        assertEquals(emptyList(), store.savedStates)
    }

    @Test
    fun `a second manager over the same store restores a tracking session as Paused with the same metrics`() =
        runTest(testScheduler) {
            locationRepository.setUpdatesFlow(updates)
            manager.start(point1)
            testScheduler.runCurrent()
            emitFix(point2)
            val metrics = assertIs<TrackingState.Tracking>(manager.currentState.value).metrics
            val secondLocationRepository = FakeLocationRepository()
            val secondLauncher = FakeTrackingServiceLauncher()
            val restoredManager = newManager(secondLocationRepository, secondLauncher)

            val restored = restoredManager.restore()

            assertEquals(TrackingState.Paused(metrics), restored)
            assertEquals(restored, restoredManager.currentState.value)
            assertEquals(0, secondLocationRepository.observeCallCount)
            assertEquals(0, secondLauncher.startCallCount)
        }

    @Test
    fun `a paused session is restored as Paused`() = runTest(testScheduler) {
        val metrics = metrics()
        store.stored = TrackingState.Paused(metrics)

        assertEquals(TrackingState.Paused(metrics), manager.restore())
    }

    @Test
    fun `a finished session stays Finished and starts nothing`() = runTest(testScheduler) {
        val metrics = metrics()
        store.stored = TrackingState.Finished(metrics)

        val restored = manager.restore()

        assertEquals(TrackingState.Finished(metrics), restored)
        assertEquals(TrackingState.Finished(metrics), manager.currentState.value)
        assertEquals(0, locationRepository.observeCallCount)
        assertEquals(0, launcher.startCallCount)
    }

    @Test
    fun `restore without a stored session is Idle`() = runTest(testScheduler) {
        assertEquals(TrackingState.Idle, manager.restore())
        assertEquals(TrackingState.Idle, manager.currentState.value)
    }

    @Test
    fun `restore does not replace a session that is already running`() = runTest(testScheduler) {
        store.stored = TrackingState.Finished(metrics())
        manager.start(point1)
        testScheduler.runCurrent()
        val running = manager.currentState.value

        assertEquals(running, manager.restore())
        assertEquals(running, manager.currentState.value)
    }

    @Test
    fun `a session started while restore loads is not replaced`() = runTest(testScheduler) {
        store.stored = TrackingState.Finished(metrics())
        val gate = CompletableDeferred<Unit>()
        store.loadGate = gate
        val restoring = async { manager.restore() }
        testScheduler.runCurrent()

        manager.start(point1)
        gate.complete(Unit)
        val result = restoring.await()

        assertIs<TrackingState.Tracking>(result)
        assertEquals(result, manager.currentState.value)
    }

    @Test
    fun `a failing load propagates out of restore and leaves the state Idle`() = runTest(testScheduler) {
        store.loadFailure = IllegalStateException("unreadable")

        assertFailsWith<IllegalStateException> { manager.restore() }
        assertEquals(TrackingState.Idle, manager.currentState.value)
    }

    @Test
    fun `clearSession clears the store`() = runTest(testScheduler) {
        store.stored = TrackingState.Finished(metrics())

        manager.clearSession()

        assertEquals(1, store.clearCallCount)
        assertEquals(null, store.stored)
    }

    @Test
    fun `a save still pending when the session is cleared does not bring it back`() = runTest(testScheduler) {
        manager.start(point1)
        manager.stop()

        manager.clearSession()
        testScheduler.runCurrent()

        assertEquals(null, store.stored)
    }

    @Test
    fun `a new session after clearSession is saved again`() = runTest(testScheduler) {
        manager.start(point1)
        manager.stop()
        manager.clearSession()
        testScheduler.runCurrent()

        manager.start(point2)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(store.stored)
    }

    @Test
    fun `a failing clear is logged and does not throw`() = runTest(testScheduler) {
        store.clearFailure = IllegalStateException("disk full")

        manager.clearSession()

        assertTrue(logger.loggedMessages.any { "disk full" in it.second })
    }

    @Test
    fun `a failing store does not stop tracking and a later save succeeds`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        store.saveFailure = IllegalStateException("disk full")

        manager.start(point1)
        testScheduler.runCurrent()
        emitFix(point2)

        val tracking = assertIs<TrackingState.Tracking>(manager.currentState.value)
        assertEquals(listOf(point1, point2), tracking.metrics.path)
        assertTrue(logger.loggedMessages.any { "disk full" in it.second })
        assertEquals(emptyList(), store.savedStates)

        store.saveFailure = null
        manager.pause()
        testScheduler.runCurrent()

        assertEquals(TrackingState.Paused(tracking.metrics), store.stored)
    }

    private suspend fun emitFix(coordinates: Coordinates) {
        updates.emit(LocationUpdate.Success(coordinates, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.advanceUntilIdle()
    }

    private fun metrics() = TrackingMetrics(
        elapsedMillis = 5_000L,
        lastUpdateElapsedRealtimeMillis = 9_000L,
        distanceMeters = 42.0,
        path = listOf(point1, point2),
        currentSpeedMetersPerSecond = 1.5f
    )
}
