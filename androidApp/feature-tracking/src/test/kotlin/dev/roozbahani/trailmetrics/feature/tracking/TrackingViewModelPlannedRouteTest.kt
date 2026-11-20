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
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.TrackingMetricsUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The plan a [TrackingViewModel] was opened with is kept with the session it starts, so a recreated Tracking
 * screen can be offered it again (the offer reads it from the session, never from the route draft).
 */
class TrackingViewModelPlannedRouteTest {

    private val testScheduler = TestCoroutineScheduler()
    private val clock = FakeClock(nowMillis = 1_000_000L, elapsedRealtimeMillis = 5_000L)
    private val store = FakeTrackingSessionStore()
    private val locationRepository = FakeLocationRepository()
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

    private fun TestScope.createViewModel(plannedRoutePoints: List<Coordinates>): TrackingViewModel {
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
        return TrackingViewModel(
            trackingSessionManager = sessionManager,
            userProfileRepository = FakeUserProfileRepository(UserProfile(weightKg = 70.0)),
            trackingMetricsUseCase = TrackingMetricsUseCase(CalorieCalculator()),
            saveActivityUseCase = SaveActivityUseCase(FakeActivityHistoryRepository(), CalorieCalculator(), clock),
            activityType = ActivityType.Cycling,
            plannedRoutePoints = plannedRoutePoints,
            clock = clock,
            snapshotFileDeleter = FakeSnapshotFileDeleter()
        ).also { testScheduler.runCurrent() }
    }

    @Test
    fun `start keeps the planned route with the session and stores it`() = runTest(testScheduler) {
        val viewModel = createViewModel(PLAN)

        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        assertEquals(PLAN, sessionManager.sessionDetails.value?.plannedRoute)
        assertEquals(PLAN, store.storedPlannedRoute)
    }

    @Test
    fun `granting location permission also keeps the planned route with the session`() = runTest(testScheduler) {
        val viewModel = createViewModel(PLAN)

        viewModel.onAction(TrackingAction.LocationPermissionGranted(START))
        testScheduler.runCurrent()

        assertEquals(PLAN, sessionManager.sessionDetails.value?.plannedRoute)
        assertEquals(PLAN, store.storedPlannedRoute)
    }

    @Test
    fun `start with no planned route stores an empty plan`() = runTest(testScheduler) {
        val viewModel = createViewModel(emptyList())

        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        assertEquals(emptyList(), sessionManager.sessionDetails.value?.plannedRoute)
        assertEquals(emptyList(), store.storedPlannedRoute)
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `the session ends at the route's end while nobody collects the state`() = runTest(testScheduler) {
        // No collector: the screen is locked. The manager keeps running and ends the session by itself.
        val viewModel = createViewModel(PLAN)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        clock.elapsedRealtimeMillis = 5_000L + 60_000L
        locationRepository.emit(LocationUpdate.Success(PLAN.last(), speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.runCurrent()

        // The screen is shown again: collecting the state now gives the finished session.
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
        testScheduler.runCurrent()
        val state = viewModel.state.value
        assertIs<TrackingState.Finished>(state.trackingState)
        assertTrue(state.canSave)
        assertEquals(PLAN, assertNotNull(state.routeProgress).traveledSegment)
    }

    private companion object {
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        val PLAN = listOf(START, Coordinates(latitude = 52.001, longitude = 13.000), Coordinates(52.002, 13.000))
    }
}
