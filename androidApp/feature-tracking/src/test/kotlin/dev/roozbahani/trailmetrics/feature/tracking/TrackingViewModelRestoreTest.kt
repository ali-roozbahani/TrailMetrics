package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeClock
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeLogger
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeTrackingSessionStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** [TrackingViewModel] over a stored session: what it restores, and when Start is allowed. */
class TrackingViewModelRestoreTest {

    private val testScheduler = TestCoroutineScheduler()
    private val locationRepository = FakeLocationRepository()
    private val launcher = FakeTrackingServiceLauncher()
    private val clock = FakeClock(nowMillis = NOW, elapsedRealtimeMillis = 5_000L)
    private val userProfileRepository = FakeUserProfileRepository(UserProfile(weightKg = 70.0))
    private val activityHistoryRepository = FakeActivityHistoryRepository()
    private val store = FakeTrackingSessionStore()
    private lateinit var sessionManager: TrackingSessionManager

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun TestScope.newSessionManager() = TrackingSessionManager(
        locationRepository = locationRepository,
        updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
        trackingServiceLauncher = launcher,
        speedCalculator = SpeedCalculator(),
        clock = clock,
        logger = FakeLogger(),
        trackingSessionStore = store,
        scope = backgroundScope
    )

    /** A ViewModel over [manager] (a new one over the store by default), with a state subscriber. */
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.createViewModel(
        manager: TrackingSessionManager = newSessionManager(),
        plannedRoutePoints: List<Coordinates> = emptyList()
    ): TrackingViewModel {
        sessionManager = manager
        val viewModel = TrackingViewModel(
            trackingSessionManager = manager,
            userProfileRepository = userProfileRepository,
            calorieCalculator = CalorieCalculator(),
            saveActivityUseCase = SaveActivityUseCase(activityHistoryRepository, CalorieCalculator(), clock),
            activityType = ActivityType.Cycling,
            plannedRoutePoints = plannedRoutePoints,
            clock = clock
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
        testScheduler.runCurrent()
        return viewModel
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.collectEvents(viewModel: TrackingViewModel): List<TrackingEvent> {
        val events = mutableListOf<TrackingEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        return events
    }

    private fun storeSession(state: TrackingState, startedAt: Long? = STORED_STARTED_AT) {
        store.stored = state
        store.storedActivityType = ActivityType.Cycling
        store.storedStartedAtEpochMillis = startedAt
    }

    // region what is restored

    @Test
    fun `a stored Tracking session is restored Paused`() = runTest(testScheduler) {
        storeSession(TrackingState.Tracking(METRICS))

        val viewModel = createViewModel()

        val state = viewModel.state.value
        assertEquals(TrackingState.Paused(METRICS), state.trackingState)
        assertTrue(state.canResume)
        assertFalse(state.canStart)
        assertEquals(METRICS, state.currentMetrics)
    }

    @Test
    fun `a stored Paused session is restored Paused`() = runTest(testScheduler) {
        storeSession(TrackingState.Paused(METRICS))

        val viewModel = createViewModel()

        assertEquals(TrackingState.Paused(METRICS), viewModel.state.value.trackingState)
        assertFalse(viewModel.state.value.canStart)
    }

    @Test
    fun `a stored Finished session is restored Finished with its metrics and no Start`() = runTest(testScheduler) {
        storeSession(TrackingState.Finished(METRICS))

        val viewModel = createViewModel()

        val state = viewModel.state.value
        assertEquals(TrackingState.Finished(METRICS), state.trackingState)
        assertEquals(METRICS, state.currentMetrics)
        assertFalse(state.canStart)
    }

    @Test
    fun `a restored session starts no recording and no service`() = runTest(testScheduler) {
        storeSession(TrackingState.Tracking(METRICS))

        createViewModel()

        assertEquals(0, locationRepository.observeLocationUpdatesCalls)
        assertEquals(0, launcher.startCalls)
    }

    @Test
    fun `Resume on a restored session records again`() = runTest(testScheduler) {
        storeSession(TrackingState.Paused(METRICS))
        val viewModel = createViewModel()

        viewModel.onAction(TrackingAction.Resume)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
        assertEquals(1, locationRepository.observeLocationUpdatesCalls)
    }

    @Test
    fun `a new ViewModel over a running manager keeps the live session`() = runTest(testScheduler) {
        val manager = newSessionManager()
        manager.start(START, ActivityType.Cycling)
        testScheduler.runCurrent()
        val running = manager.currentState.value
        storeSession(TrackingState.Finished(METRICS))

        val viewModel = createViewModel(manager)

        assertEquals(running, viewModel.state.value.trackingState)
        assertFalse(viewModel.state.value.canStart)
    }

    // endregion

    // region Start while restoring

    @Test
    fun `before the stored session is loaded Start is not possible and a Start action starts nothing`() =
        runTest(testScheduler) {
            val gate = CompletableDeferred<Unit>()
            store.loadGate = gate
            val viewModel = createViewModel()

            assertTrue(viewModel.state.value.isRestoring)
            assertFalse(viewModel.state.value.canStart)
            viewModel.onAction(TrackingAction.Start(START))
            viewModel.onAction(TrackingAction.LocationPermissionGranted(START))
            testScheduler.runCurrent()
            assertEquals(TrackingState.Idle, viewModel.state.value.trackingState)
            assertEquals(0, launcher.startCalls)

            gate.complete(Unit)
            testScheduler.runCurrent()
            assertFalse(viewModel.state.value.isRestoring)
            assertTrue(viewModel.state.value.canStart)
        }

    @Test
    fun `with nothing stored Start becomes possible and starts a session`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        assertTrue(viewModel.state.value.canStart)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
    }

    @Test
    fun `a failing load shows an error and Start becomes possible`() = runTest(testScheduler) {
        store.loadFailure = IllegalStateException("unreadable")
        val manager = newSessionManager()
        val events = mutableListOf<TrackingEvent>()
        val viewModel = createViewModel(manager)
        // The error is sent while the ViewModel is created, so it is buffered until a collector subscribes.
        events += collectEvents(viewModel)
        testScheduler.runCurrent()

        assertEquals(listOf<TrackingEvent>(TrackingEvent.ShowError(RouteUiError.General)), events)
        assertTrue(viewModel.state.value.canStart)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
    }

    @Test
    fun `Start is impossible in Finished after the route's end stopped the session`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        sessionManager.stop()
        testScheduler.runCurrent()
        val finished = viewModel.state.value.trackingState
        assertIs<TrackingState.Finished>(finished)
        assertFalse(viewModel.state.value.canStart)

        viewModel.onAction(TrackingAction.Start(NEXT))
        testScheduler.runCurrent()

        assertEquals(finished, viewModel.state.value.trackingState)
        assertEquals(finished, store.stored)
    }

    @Test
    fun `Start is impossible in a restored Finished session and the stored one is kept`() = runTest(testScheduler) {
        storeSession(TrackingState.Finished(METRICS))
        val viewModel = createViewModel()

        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        assertEquals(TrackingState.Finished(METRICS), viewModel.state.value.trackingState)
        assertEquals(TrackingState.Finished(METRICS), store.stored)
    }

    // endregion

    // region Finish on a restored session

    @Test
    fun `Finish on a restored session saves it with the stored start time`() = runTest(testScheduler) {
        storeSession(TrackingState.Finished(METRICS))
        val viewModel = createViewModel()

        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        val saved = activityHistoryRepository.savedActivities.single()
        assertEquals(STORED_STARTED_AT, saved.startedAtEpochMillis)
        assertNull(store.stored)
    }

    @Test
    fun `Finish on a restored session without a stored start time uses the estimate`() = runTest(testScheduler) {
        storeSession(TrackingState.Finished(METRICS), startedAt = null)
        val viewModel = createViewModel()

        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        val saved = activityHistoryRepository.savedActivities.single()
        assertEquals(NOW - METRICS.elapsedMillis, saved.startedAtEpochMillis)
    }

    @Test
    fun `a failed save keeps the restored session so Finish can be retried`() = runTest(testScheduler) {
        storeSession(TrackingState.Finished(METRICS))
        val viewModel = createViewModel()
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()
        assertEquals(TrackingState.Finished(METRICS), viewModel.state.value.trackingState)
        assertEquals(TrackingState.Finished(METRICS), store.stored)

        activityHistoryRepository.saveActivityFailure = null
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        assertEquals(1, activityHistoryRepository.savedActivities.size)
        assertEquals(TrackingState.Idle, viewModel.state.value.trackingState)
    }

    // endregion

    // region the next Tracking screen after a session ended

    @Test
    fun `after Stop discarded the session a new ViewModel over the same manager shows Start`() =
        runTest(testScheduler) {
            val manager = newSessionManager()
            val first = createViewModel(manager)
            first.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()
            first.onAction(TrackingAction.Stop)
            testScheduler.runCurrent()
            assertNull(store.stored)

            val second = createViewModel(manager)

            assertEquals(TrackingState.Idle, second.state.value.trackingState)
            assertTrue(second.state.value.canStart)
            second.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()
            assertIs<TrackingState.Tracking>(second.state.value.trackingState)
        }

    @Test
    fun `after the route's end and a saved Finish a new ViewModel over the same manager shows Start`() =
        runTest(testScheduler) {
            val manager = newSessionManager()
            val first = createViewModel(manager)
            first.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()
            manager.stop()
            testScheduler.runCurrent()
            first.onAction(TrackingAction.Finish(snapshotFilePath = null))
            testScheduler.runCurrent()
            assertEquals(1, activityHistoryRepository.savedActivities.size)
            assertNull(store.stored)

            val second = createViewModel(manager)

            assertTrue(second.state.value.canStart)
            second.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()
            assertIs<TrackingState.Tracking>(second.state.value.trackingState)
        }

    @Test
    fun `a restored session left with Back and reopened is still offered`() = runTest(testScheduler) {
        storeSession(TrackingState.Finished(METRICS))
        val manager = newSessionManager()
        createViewModel(manager)

        val reopened = createViewModel(manager)

        assertEquals(TrackingState.Finished(METRICS), reopened.state.value.trackingState)
        assertFalse(reopened.state.value.canStart)
    }

    // endregion

    private companion object {
        const val NOW = 1_000_000L
        const val STORED_STARTED_AT = 777_000L
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        val NEXT = Coordinates(latitude = 52.001, longitude = 13.000)
        val METRICS = TrackingMetrics(
            elapsedMillis = 60_000L,
            lastUpdateElapsedRealtimeMillis = 60_000L,
            distanceMeters = 166.0,
            path = listOf(START, NEXT)
        )
    }
}
