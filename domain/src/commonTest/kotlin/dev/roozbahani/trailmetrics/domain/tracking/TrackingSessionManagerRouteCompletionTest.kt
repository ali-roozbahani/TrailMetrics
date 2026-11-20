package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.fakes.FakeClock
import dev.roozbahani.trailmetrics.domain.fakes.FakeLocationRepository
import dev.roozbahani.trailmetrics.domain.fakes.FakeLogger
import dev.roozbahani.trailmetrics.domain.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.fakes.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
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
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** The manager ends a planned session by itself at the route's end; nothing here collects any flow of it. */
class TrackingSessionManagerRouteCompletionTest {

    private val testScheduler = TestCoroutineScheduler()
    private val testScope = TestScope(StandardTestDispatcher(testScheduler))
    private val store = FakeTrackingSessionStore()
    private val launcher = FakeTrackingServiceLauncher()
    private val locationRepository = FakeLocationRepository()
    private val updates = MutableSharedFlow<LocationUpdate>()
    private val manager = newManager(locationRepository, launcher)

    private fun newManager(locations: FakeLocationRepository, serviceLauncher: FakeTrackingServiceLauncher) =
        TrackingSessionManager(
            locationRepository = locations,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = serviceLauncher,
            speedCalculator = SpeedCalculator(),
            clock = FakeClock(),
            logger = FakeLogger(),
            trackingSessionStore = store,
            scope = testScope
        )

    private suspend fun fix(point: Coordinates) {
        updates.emit(LocationUpdate.Success(coordinates = point, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.runCurrent()
    }

    private fun startPlanned(plan: List<Coordinates> = ROUTE) {
        locationRepository.setUpdatesFlow(updates)
        manager.start(plan.first(), ActivityType.Running, plan)
        testScheduler.runCurrent()
    }

    @Test
    fun `the session ends at the route's end with nobody collecting any flow`() = runTest(testScheduler) {
        startPlanned()

        ROUTE.drop(1).forEach { fix(it) }

        assertIs<TrackingState.Finished>(manager.currentState.value)
        assertEquals(1, launcher.stopCallCount)
        assertEquals(0, store.clearCallCount)
        assertIs<TrackingState.Finished>(store.stored)
    }

    @Test
    fun `progress advances with each fix while nothing collects`() = runTest(testScheduler) {
        startPlanned()
        assertNull(manager.routeProgress.value)

        fix(ROUTE[1])
        assertEquals(1, assertNotNull(manager.routeProgress.value).lastIndex)
        fix(ROUTE[3])
        assertEquals(3, assertNotNull(manager.routeProgress.value).lastIndex)
    }

    @Test
    fun `a plan-less session never ends by itself`() = runTest(testScheduler) {
        locationRepository.setUpdatesFlow(updates)
        manager.start(ROUTE.first(), ActivityType.Running)
        testScheduler.runCurrent()

        ROUTE.drop(1).forEach { fix(it) }

        assertIs<TrackingState.Tracking>(manager.currentState.value)
        assertNull(manager.routeProgress.value)
        assertEquals(0, launcher.stopCallCount)
    }

    @Test
    fun `a paused session does not end until the first fix after resume`() = runTest(testScheduler) {
        startPlanned()
        fix(ROUTE[1])
        manager.pause()
        testScheduler.runCurrent()

        assertIs<TrackingState.Paused>(manager.currentState.value)
        assertEquals(0, launcher.stopCallCount)

        manager.resume()
        testScheduler.runCurrent()
        assertIs<TrackingState.Tracking>(manager.currentState.value)
        fix(ROUTE.last())

        assertIs<TrackingState.Finished>(manager.currentState.value)
        assertEquals(1, launcher.stopCallCount)
    }

    @Test
    fun `the session ends once and not at each later fix`() = runTest(testScheduler) {
        startPlanned()
        ROUTE.drop(1).forEach { fix(it) }

        fix(ROUTE.last())
        fix(ROUTE.last())

        assertEquals(1, launcher.stopCallCount)
        assertIs<TrackingState.Finished>(manager.currentState.value)
    }

    @Test
    fun `a second session after discard ends again`() = runTest(testScheduler) {
        startPlanned()
        ROUTE.drop(1).forEach { fix(it) }
        manager.discard()
        assertIs<TrackingState.Idle>(manager.currentState.value)

        startPlanned()
        assertNull(manager.routeProgress.value)
        ROUTE.drop(1).forEach { fix(it) }

        assertIs<TrackingState.Finished>(manager.currentState.value)
        assertEquals(2, launcher.stopCallCount)
    }

    @Test
    fun `a restored session starts progress from index 0`() = runTest(testScheduler) {
        startPlanned()
        fix(ROUTE[1])
        testScheduler.runCurrent()
        val secondLocations = FakeLocationRepository().also { it.setUpdatesFlow(updates) }
        val restoredManager = newManager(secondLocations, FakeTrackingServiceLauncher())

        restoredManager.restore()
        assertNull(restoredManager.routeProgress.value)
        restoredManager.resume()
        testScheduler.runCurrent()
        fix(ROUTE[3])

        assertEquals(3, assertNotNull(restoredManager.routeProgress.value).lastIndex)
    }

    @Test
    fun `the completing fix is the last point of the path`() = runTest(testScheduler) {
        startPlanned()
        ROUTE.drop(1).forEach { fix(it) }

        val finished = assertIs<TrackingState.Finished>(manager.currentState.value)

        // ROUTE[5] is the first fix within the last three points and 25 m of the end: the later fixes are not recorded.
        assertEquals(ROUTE[5], finished.metrics.path.last())
        assertEquals(ROUTE.subList(0, 6), finished.metrics.path)
    }

    @Test
    fun `stop is a no-op in idle and finished`() = runTest(testScheduler) {
        manager.stop()
        testScheduler.runCurrent()

        assertIs<TrackingState.Idle>(manager.currentState.value)
        assertEquals(0, launcher.stopCallCount)
        assertEquals(emptyList(), store.savedStates)

        startPlanned()
        manager.stop()
        testScheduler.runCurrent()
        manager.stop()
        testScheduler.runCurrent()

        assertIs<TrackingState.Finished>(manager.currentState.value)
        assertEquals(1, launcher.stopCallCount)
        assertEquals(1, store.savedStates.count { it is TrackingState.Finished })
    }

    private companion object {
        /** Eight points: five ~111 m apart, then three ~5.6 m apart; the last three count as the end. */
        val ROUTE = listOf(0.0, 0.001, 0.002, 0.003, 0.00400, 0.00405, 0.00410, 0.00415)
            .map { Coordinates(latitude = 52.0 + it, longitude = 13.0) }
    }
}
