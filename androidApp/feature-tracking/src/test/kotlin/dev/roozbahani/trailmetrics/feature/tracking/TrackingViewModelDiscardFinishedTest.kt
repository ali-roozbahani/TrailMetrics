package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeClock
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeSnapshotFileDeleter
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.TrackingMetricsUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
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

/**
 * [TrackingAction.DiscardFinished]: offered for a finished session only (`domain`'s `canDiscard`), it deletes the
 * session without saving it and the screen stays, Idle with Start offered.
 */
class TrackingViewModelDiscardFinishedTest {

    private val testScheduler = TestCoroutineScheduler()
    private val locationRepository = FakeLocationRepository()
    private val clock = FakeClock(nowMillis = 1_000_000L, elapsedRealtimeMillis = 5_000L)
    private val userProfileRepository = FakeUserProfileRepository(UserProfile(weightKg = 70.0))
    private val activityHistoryRepository = FakeActivityHistoryRepository()
    private val store = FakeTrackingSessionStore()
    private val snapshotFileDeleter = FakeSnapshotFileDeleter()
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

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.createViewModel(): TrackingViewModel {
        sessionManager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = FakeTrackingServiceLauncher(),
            speedCalculator = SpeedCalculator(),
            clock = clock,
            logger = FakeLogger(),
            trackingSessionStore = store,
            scope = backgroundScope
        )
        val viewModel = TrackingViewModel(
            trackingSessionManager = sessionManager,
            userProfileRepository = userProfileRepository,
            trackingMetricsUseCase = TrackingMetricsUseCase(CalorieCalculator()),
            saveActivityUseCase = SaveActivityUseCase(activityHistoryRepository, CalorieCalculator(), clock),
            activityType = ActivityType.Cycling,
            plannedRoutePoints = emptyList(),
            clock = clock,
            snapshotFileDeleter = snapshotFileDeleter
        )
        // state is stateIn(WhileSubscribed): keep a subscriber for the whole test.
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
        testScheduler.runCurrent()
        return viewModel
    }

    private fun start(viewModel: TrackingViewModel) {
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
    }

    /** Starts a session and stops it through the manager, as the route's end does: Finished and stored. */
    private fun startAndFinishSession(viewModel: TrackingViewModel) {
        start(viewModel)
        sessionManager.stop()
        testScheduler.runCurrent()
        assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)
        assertIs<TrackingState.Finished>(store.stored)
    }

    @Test
    fun `Discard is offered for a finished session only`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        assertFalse(viewModel.state.value.canDiscard, "idle")

        start(viewModel)
        assertFalse(viewModel.state.value.canDiscard, "tracking")

        viewModel.onAction(TrackingAction.Pause)
        testScheduler.runCurrent()
        assertIs<TrackingState.Paused>(viewModel.state.value.trackingState)
        assertFalse(viewModel.state.value.canDiscard, "paused")

        viewModel.onAction(TrackingAction.Resume)
        testScheduler.runCurrent()
        sessionManager.stop()
        testScheduler.runCurrent()
        assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)
        assertTrue(viewModel.state.value.canDiscard, "finished")
        assertTrue(viewModel.state.value.canSave, "finished")
    }

    @Test
    fun `a discarded finished session becomes Idle, its stored copy is cleared and Start is offered`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            startAndFinishSession(viewModel)
            assertFalse(viewModel.state.value.canStart)

            viewModel.onAction(TrackingAction.DiscardFinished)
            testScheduler.runCurrent()

            assertEquals(TrackingState.Idle, viewModel.state.value.trackingState)
            assertNull(store.stored)
            assertEquals(1, store.clearCallCount)
            assertEquals(emptyList(), activityHistoryRepository.savedActivities)
            assertTrue(viewModel.state.value.canStart)
            assertFalse(viewModel.state.value.canDiscard)
            assertFalse(viewModel.state.value.canSave)
        }

    @Test
    fun `Start after a discard begins a new session`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        startAndFinishSession(viewModel)
        viewModel.onAction(TrackingAction.DiscardFinished)
        testScheduler.runCurrent()

        start(viewModel)

        assertIs<TrackingState.Tracking>(store.stored)
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `a discard emits no event, so the screen stays`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = mutableListOf<TrackingEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        startAndFinishSession(viewModel)

        viewModel.onAction(TrackingAction.DiscardFinished)
        testScheduler.runCurrent()

        assertEquals(emptyList(), events)
    }

    @Test
    fun `DiscardFinished does nothing while tracking or paused`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        start(viewModel)

        viewModel.onAction(TrackingAction.DiscardFinished)
        testScheduler.runCurrent()
        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
        assertIs<TrackingState.Tracking>(store.stored)

        viewModel.onAction(TrackingAction.Pause)
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.DiscardFinished)
        testScheduler.runCurrent()
        assertIs<TrackingState.Paused>(viewModel.state.value.trackingState)
        assertIs<TrackingState.Paused>(store.stored)
        assertEquals(0, store.clearCallCount)
    }

    @Test
    fun `DiscardFinished does nothing while a Finish is saving the session`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        startAndFinishSession(viewModel)
        val gate = CompletableDeferred<Unit>()
        activityHistoryRepository.saveActivityGate = gate
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        viewModel.onAction(TrackingAction.DiscardFinished)
        testScheduler.runCurrent()
        assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)
        assertEquals(0, store.clearCallCount)

        gate.complete(Unit)
        testScheduler.runCurrent()
        assertEquals(1, activityHistoryRepository.savedActivities.size)
        assertNull(store.stored)
    }

    @Test
    fun `a discard deletes the snapshot file kept for a retry`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        startAndFinishSession(viewModel)
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = SNAPSHOT))
        testScheduler.runCurrent()
        assertEquals(SNAPSHOT, viewModel.state.value.retainedSnapshotPath)
        assertEquals(emptyList(), snapshotFileDeleter.requestedPaths)

        viewModel.onAction(TrackingAction.DiscardFinished)
        testScheduler.runCurrent()

        assertEquals(listOf<String?>(SNAPSHOT), snapshotFileDeleter.completedPaths)
        assertNull(viewModel.state.value.retainedSnapshotPath)
        assertEquals(TrackingState.Idle, viewModel.state.value.trackingState)
        assertEquals(1, store.clearCallCount)
    }

    private companion object {
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        const val SNAPSHOT = "/snapshots/retained.png"
    }
}
