package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.core.testing.FakeClock
import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingSessionStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * When [TrackingViewModel] clears the stored session: after a saved activity and on Stop (the screen
 * leaves right after it), never after a failed save, and not on a stop the route's end causes.
 */
class TrackingViewModelStoredSessionTest {

    private val testScheduler = TestCoroutineScheduler()
    private val locationRepository = FakeLocationRepository()
    private val clock = FakeClock(nowMillis = 1_000_000L, elapsedRealtimeMillis = 5_000L)
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
            calorieCalculator = CalorieCalculator(),
            saveActivityUseCase = SaveActivityUseCase(activityHistoryRepository, CalorieCalculator(), clock),
            activityType = ActivityType.Cycling,
            plannedRoutePoints = emptyList(),
            clock = clock
        )
        testScheduler.runCurrent()
        return viewModel
    }

    /** Starts a session and stops it through the manager, as the route's end does: Finished and stored. */
    private fun startAndFinishSession(viewModel: TrackingViewModel) {
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        sessionManager.stop()
        testScheduler.runCurrent()
        assertIs<TrackingState.Finished>(store.stored)
    }

    @Test
    fun `the stored session is cleared after a successful save`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        startAndFinishSession(viewModel)

        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        assertEquals(1, activityHistoryRepository.savedActivities.size)
        assertNull(store.stored)
    }

    @Test
    fun `the stored session is kept after a failed save`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        startAndFinishSession(viewModel)
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")

        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        assertEquals(emptyList(), activityHistoryRepository.savedActivities)
        assertIs<TrackingState.Finished>(store.stored)
        assertEquals(0, store.clearCallCount)
    }

    @Test
    fun `the stored session is cleared once a retry saves`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        startAndFinishSession(viewModel)
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        activityHistoryRepository.saveActivityFailure = null
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
        testScheduler.runCurrent()

        assertNull(store.stored)
    }

    @Test
    fun `Stop discards the session and clears the stored one`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        assertNotNull(store.stored)

        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()

        assertNull(store.stored)
        assertEquals(emptyList(), activityHistoryRepository.savedActivities)
    }

    @Test
    fun `a stop the manager makes by itself keeps the stored session`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        startAndFinishSession(viewModel)

        assertIs<TrackingState.Finished>(store.stored)
        assertEquals(0, store.clearCallCount)
    }

    private companion object {
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
    }
}
