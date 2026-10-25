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
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** What [TrackingSessionManager] writes to its [TrackingSessionStore], and what restore reads back. */
class TrackingSessionManagerPersistenceTest {

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.327, 12.394)
    private val testScheduler = TestCoroutineScheduler()
    private val testScope = TestScope(StandardTestDispatcher(testScheduler))
    private val store = FakeTrackingSessionStore()
    private val logger = FakeLogger()
    private val clock = FakeClock().also { it.setElapsedRealtimeValues(0L, 1_000L, 2_000L, 3_000L, 4_000L) }
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
        clock = clock,
        logger = logger,
        trackingSessionStore = store,
        scope = testScope
    )

    @Test
    fun `every state the manager moves to is saved in order`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        val seen = mutableListOf<TrackingState>()

        manager.start(point1, ActivityType.Running)
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
            manager.start(point1, ActivityType.Running)
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
    fun `start saves the activity type and the start time with every state`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        clock.setWallClockValues(STARTED_AT)

        manager.start(point1, ActivityType.Cycling)
        testScheduler.runCurrent()
        emitFix(point2)
        manager.pause()
        testScheduler.runCurrent()

        assertEquals(SessionDetails(ActivityType.Cycling, STARTED_AT), manager.sessionDetails.value)
        assertEquals(ActivityType.Cycling, store.storedActivityType)
        assertEquals(STARTED_AT, store.storedStartedAtEpochMillis)
        assertEquals(3, store.savedStates.size)
    }

    @Test
    fun `restore returns the stored type and start time and a second manager saves them again`() =
        runTest(testScheduler) {
            locationRepository.setUpdatesFlow(updates)
            clock.setWallClockValues(STARTED_AT)
            manager.start(point1, ActivityType.Walking)
            testScheduler.runCurrent()
            // The restored manager must take the start time from the store, not read the clock again.
            clock.setWallClockValues(STARTED_AT + 3_600_000)
            val restoredManager = newManager(FakeLocationRepository(), FakeTrackingServiceLauncher())

            restoredManager.restore()
            restoredManager.resume()
            testScheduler.runCurrent()

            assertEquals(SessionDetails(ActivityType.Walking, STARTED_AT), restoredManager.sessionDetails.value)
            assertIs<TrackingState.Tracking>(store.stored)
            assertEquals(ActivityType.Walking, store.storedActivityType)
            assertEquals(STARTED_AT, store.storedStartedAtEpochMillis)
        }

    @Test
    fun `a stored session without a type or start time restores with both null`() = runTest(testScheduler) {
        store.stored = TrackingState.Paused(metrics())

        manager.restore()

        assertEquals(SessionDetails(null, null), manager.sessionDetails.value)
    }

    @Test
    fun `restore without a stored session leaves the details null`() = runTest(testScheduler) {
        manager.restore()

        assertNull(manager.sessionDetails.value)
    }

    @Test
    fun `restore does not replace the details of a session started while it loads`() = runTest(testScheduler) {
        store.stored = TrackingState.Paused(metrics())
        store.storedActivityType = ActivityType.Walking
        store.storedStartedAtEpochMillis = STARTED_AT
        clock.setWallClockValues(STARTED_AT + 5)
        val gate = CompletableDeferred<Unit>()
        store.loadGate = gate
        val restoring = async { manager.restore() }
        testScheduler.runCurrent()

        manager.start(point1, ActivityType.Running)
        gate.complete(Unit)
        restoring.await()

        assertEquals(SessionDetails(ActivityType.Running, STARTED_AT + 5), manager.sessionDetails.value)
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
        manager.start(point1, ActivityType.Running)
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

        manager.start(point1, ActivityType.Running)
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
        manager.start(point1, ActivityType.Running)
        manager.stop()

        manager.clearSession()
        testScheduler.runCurrent()

        assertEquals(null, store.stored)
    }

    @Test
    fun `a new session after clearSession is saved again`() = runTest(testScheduler) {
        manager.start(point1, ActivityType.Running)
        manager.stop()
        manager.clearSession()
        testScheduler.runCurrent()

        manager.start(point2, ActivityType.Running)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(store.stored)
    }

    @Test
    fun `clearSession returns a Finished session to Idle and drops the details`() = runTest(testScheduler) {
        manager.start(point1, ActivityType.Running)
        manager.stop()
        testScheduler.runCurrent()
        assertIs<TrackingState.Finished>(manager.currentState.value)

        manager.clearSession()
        testScheduler.runCurrent()

        assertEquals(TrackingState.Idle, manager.currentState.value)
        assertNull(manager.sessionDetails.value)
        assertNull(store.stored)
    }

    @Test
    fun `clearSession returns a restored Finished session to Idle`() = runTest(testScheduler) {
        store.stored = TrackingState.Finished(metrics())
        store.storedActivityType = ActivityType.Walking
        store.storedStartedAtEpochMillis = STARTED_AT
        manager.restore()

        manager.clearSession()

        assertEquals(TrackingState.Idle, manager.currentState.value)
        assertNull(manager.sessionDetails.value)
    }

    @Test
    fun `clearSession leaves a Tracking or Paused session alone`() = runTest(testScheduler) {
        manager.start(point1, ActivityType.Running)
        testScheduler.runCurrent()
        val tracking = manager.currentState.value
        val details = manager.sessionDetails.value

        manager.clearSession()
        assertEquals(tracking, manager.currentState.value)
        assertEquals(details, manager.sessionDetails.value)

        manager.pause()
        testScheduler.runCurrent()
        val paused = manager.currentState.value
        manager.clearSession()

        assertIs<TrackingState.Paused>(paused)
        assertEquals(paused, manager.currentState.value)
        assertEquals(details, manager.sessionDetails.value)
    }

    @Test
    fun `a second session can start and is saved after the first was cleared`() = runTest(testScheduler) {
        manager.start(point1, ActivityType.Running)
        manager.stop()
        manager.clearSession()
        testScheduler.runCurrent()

        manager.start(point2, ActivityType.Cycling)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(manager.currentState.value)
        assertEquals(ActivityType.Cycling, manager.sessionDetails.value?.activityType)
        assertEquals(ActivityType.Cycling, store.storedActivityType)
    }

    @Test
    fun `a failing clear keeps the Finished session and its details`() = runTest(testScheduler) {
        manager.start(point1, ActivityType.Running)
        manager.stop()
        testScheduler.runCurrent()
        store.clearFailure = IllegalStateException("disk full")

        manager.clearSession()

        assertIs<TrackingState.Finished>(manager.currentState.value)
        assertEquals(ActivityType.Running, manager.sessionDetails.value?.activityType)
    }

    @Test
    fun `resume after restore starts the location observation and no second service launch`() =
        runTest(testScheduler) {
            manager.start(point1, ActivityType.Running)
            testScheduler.runCurrent()
            val secondLocationRepository = FakeLocationRepository().also { it.setUpdatesFlow(updates) }
            val secondLauncher = FakeTrackingServiceLauncher()
            val restoredManager = newManager(secondLocationRepository, secondLauncher)
            restoredManager.restore()
            assertEquals(0, secondLocationRepository.observeCallCount)

            restoredManager.resume()
            testScheduler.runCurrent()
            emitFix(point2)

            assertEquals(1, secondLocationRepository.observeCallCount)
            val tracking = assertIs<TrackingState.Tracking>(restoredManager.currentState.value)
            assertEquals(listOf(point1, point2), tracking.metrics.path)
            // resume() does not launch the service; a restored session has none until the service restore.
            assertEquals(0, secondLauncher.startCallCount)
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

        manager.start(point1, ActivityType.Running)
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

    private companion object {
        const val STARTED_AT = 1_700_000_000_000L
    }
}
