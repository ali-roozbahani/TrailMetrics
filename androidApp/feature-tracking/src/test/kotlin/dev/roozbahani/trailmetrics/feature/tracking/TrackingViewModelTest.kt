package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeClock
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeLocationRepository
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeLogger
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeUserProfileRepository
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
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TrackingViewModelTest {

    private val testScheduler = TestCoroutineScheduler()

    private val locationRepository = FakeLocationRepository()
    private val trackingServiceLauncher = FakeTrackingServiceLauncher()
    private val clock = FakeClock(nowMillis = STARTED_AT)
    private val userProfileRepository = FakeUserProfileRepository()
    private val activityHistoryRepository = FakeActivityHistoryRepository()

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

    /**
     * A real TrackingSessionManager built from fakes, running in [TestScope.backgroundScope].
     * uiState is stateIn(WhileSubscribed), so a subscriber is kept for the whole test.
     */
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.createViewModel(plannedRoutePoints: List<Coordinates> = PLANNED_ROUTE): TrackingViewModel {
        val sessionManager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = trackingServiceLauncher,
            speedCalculator = SpeedCalculator(),
            clock = clock,
            logger = FakeLogger(),
            scope = backgroundScope
        )
        val viewModel = TrackingViewModel(
            trackingSessionManager = sessionManager,
            userProfileRepository = userProfileRepository,
            calorieCalculator = CalorieCalculator(),
            saveActivityUseCase = SaveActivityUseCase(activityHistoryRepository, CalorieCalculator(), clock),
            activityType = ActivityType.Cycling,
            plannedRoutePoints = plannedRoutePoints,
            clock = clock
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
        testScheduler.runCurrent()
        return viewModel
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.collectEvents(viewModel: TrackingViewModel): List<TrackingUiEvent> {
        val events = mutableListOf<TrackingUiEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiEvents.toList(events) }
        return events
    }

    private fun receiveLocation(coordinates: Coordinates, atMillis: Long) {
        clock.nowMillis = atMillis
        locationRepository.emit(LocationUpdate.Success(coordinates, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.runCurrent()
    }

    private fun receiveUnavailable(reason: RouteError) {
        locationRepository.emit(LocationUpdate.Unavailable(reason))
        testScheduler.runCurrent()
    }

    /** Returns how many times completion was signalled. */
    private fun TrackingViewModel.finish(snapshotFilePath: String?): Int {
        var savedSignals = 0
        onFinishClicked(snapshotFilePath) { savedSignals++ }
        testScheduler.runCurrent()
        return savedSignals
    }

    // region state transitions

    @Test
    fun `initial state is Idle with no calories and only start enabled`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        val state = viewModel.uiState.value
        assertEquals(TrackingState.Idle, state.trackingState)
        assertNull(state.calories)
        assertNull(state.currentMetrics)
        assertEquals(emptyList(), state.currentPath)
        assertTrue(state.canStart)
        assertFalse(state.canPause)
        assertFalse(state.canResume)
        assertFalse(state.canStop)
    }

    @Test
    fun `start transitions to Tracking at the start point and starts the tracking service`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()

            viewModel.onStartClicked(START)
            testScheduler.runCurrent()

            val state = viewModel.uiState.value
            assertIs<TrackingState.Tracking>(state.trackingState)
            assertEquals(listOf(START), state.currentPath)
            assertFalse(state.canStart)
            assertTrue(state.canPause)
            assertTrue(state.canStop)
            assertEquals(1, trackingServiceLauncher.startCalls)
        }

    @Test
    fun `location updates while tracking extend the path and the metrics`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        receiveLocation(NEXT, atMillis = STARTED_AT + 60_000L)

        val metrics = assertNotNull(viewModel.uiState.value.currentMetrics)
        assertEquals(listOf(START, NEXT), viewModel.uiState.value.currentPath)
        assertEquals(60_000L, metrics.elapsedMillis)
        assertTrue(metrics.distanceMeters > 0.0)
    }

    @Test
    fun `pause then resume moves Tracking to Paused and back to Tracking`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        viewModel.onPauseClicked()
        testScheduler.runCurrent()
        assertIs<TrackingState.Paused>(viewModel.uiState.value.trackingState)
        assertTrue(viewModel.uiState.value.canResume)
        assertFalse(viewModel.uiState.value.canPause)
        assertTrue(viewModel.uiState.value.canStop)

        viewModel.onResumeClicked()
        testScheduler.runCurrent()
        assertIs<TrackingState.Tracking>(viewModel.uiState.value.trackingState)
        assertTrue(viewModel.uiState.value.canPause)
    }

    @Test
    fun `stop while tracking finishes the session and stops the tracking service`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        viewModel.onStopClicked()
        testScheduler.runCurrent()

        val state = viewModel.uiState.value
        assertIs<TrackingState.Finished>(state.trackingState)
        assertNull(state.currentMetrics)
        assertTrue(state.canStart)
        assertFalse(state.canStop)
        assertEquals(1, trackingServiceLauncher.stopCalls)
    }

    @Test
    fun `stop while paused finishes the session`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()
        viewModel.onPauseClicked()
        testScheduler.runCurrent()

        viewModel.onStopClicked()
        testScheduler.runCurrent()

        assertIs<TrackingState.Finished>(viewModel.uiState.value.trackingState)
    }

    @Test
    fun `granting location permission starts tracking at the given point`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        viewModel.onLocationPermissionGranted(START)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(viewModel.uiState.value.trackingState)
        assertEquals(listOf(START), viewModel.uiState.value.currentPath)
    }

    // endregion

    // region calories

    @Test
    fun `calories are null without a saved profile`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        receiveLocation(NEXT, atMillis = STARTED_AT + 60_000L)

        assertNotNull(viewModel.uiState.value.currentMetrics?.averageSpeedMetersPerSecond)
        assertNull(viewModel.uiState.value.calories)
    }

    @Test
    fun `calories are null while the average speed is unknown`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()

        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        assertNull(viewModel.uiState.value.currentMetrics?.averageSpeedMetersPerSecond)
        assertNull(viewModel.uiState.value.calories)
    }

    @Test
    fun `calories are computed from the profile weight and the average speed`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        receiveLocation(NEXT, atMillis = STARTED_AT + 60_000L)

        val metrics = assertNotNull(viewModel.uiState.value.currentMetrics)
        val expected = CalorieCalculator().calculate(
            activityType = ActivityType.Cycling,
            averageSpeedMetersPerSecond = assertNotNull(metrics.averageSpeedMetersPerSecond),
            weightKg = PROFILE.weightKg,
            durationMillis = metrics.elapsedMillis
        )
        assertEquals(expected, viewModel.uiState.value.calories)
    }

    @Test
    fun `calories are kept while paused and dropped once finished`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()
        receiveLocation(NEXT, atMillis = STARTED_AT + 60_000L)
        val trackingCalories = assertNotNull(viewModel.uiState.value.calories)

        viewModel.onPauseClicked()
        testScheduler.runCurrent()
        assertEquals(trackingCalories, viewModel.uiState.value.calories)

        viewModel.onStopClicked()
        testScheduler.runCurrent()
        assertNull(viewModel.uiState.value.calories)
    }

    // endregion

    // region finish

    @Test
    fun `finish saves the activity with the start time from Start and signals once`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()
        receiveLocation(NEXT, atMillis = STARTED_AT + 60_000L)
        clock.nowMillis = ENDED_AT
        viewModel.onStopClicked()
        testScheduler.runCurrent()
        val finished = assertIs<TrackingState.Finished>(viewModel.uiState.value.trackingState)

        val savedSignals = viewModel.finish(SNAPSHOT_PATH)

        assertEquals(1, savedSignals)
        val record = activityHistoryRepository.savedActivities.single()
        assertEquals(ActivityType.Cycling, record.activityType)
        assertEquals(STARTED_AT, record.startedAtEpochMillis)
        assertEquals(ENDED_AT, record.endedAtEpochMillis)
        assertEquals(PLANNED_ROUTE, record.plannedRoutePoints)
        assertEquals(listOf(START, NEXT), record.actualPath)
        assertEquals(finished.metrics.distanceMeters, record.distanceMeters)
        assertEquals(finished.metrics.elapsedMillis, record.durationMillis)
        assertEquals(SNAPSHOT_PATH, record.snapshotFilePath)
        assertNotNull(record.calories)
    }

    @Test
    fun `finish without a snapshot saves a record without a snapshot path`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()
        viewModel.onStopClicked()
        testScheduler.runCurrent()

        val savedSignals = viewModel.finish(snapshotFilePath = null)

        assertEquals(1, savedSignals)
        assertNull(activityHistoryRepository.savedActivities.single().snapshotFilePath)
    }

    @Test
    fun `finish before the session is finished saves nothing and does not signal`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        val savedSignals = viewModel.finish(SNAPSHOT_PATH)

        assertEquals(0, savedSignals)
        assertEquals(emptyList(), activityHistoryRepository.savedActivities)
    }

    @Test
    fun `finish without a saved profile saves nothing and does not signal`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()
        viewModel.onStopClicked()
        testScheduler.runCurrent()

        val savedSignals = viewModel.finish(SNAPSHOT_PATH)

        assertEquals(0, savedSignals)
        assertEquals(emptyList(), activityHistoryRepository.savedActivities)
    }

    // endregion

    // region location issues

    @Test
    fun `missing location permission is mapped to RequestLocationPermission`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        repeat(UNAVAILABLE_THRESHOLD) { receiveUnavailable(RouteError.MissingLocationPermission()) }

        assertEquals(listOf<TrackingUiEvent>(TrackingUiEvent.RequestLocationPermission), events)
    }

    @Test
    fun `other location errors are mapped to ShowError`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.onStartClicked(START)
        testScheduler.runCurrent()

        repeat(UNAVAILABLE_THRESHOLD) { receiveUnavailable(RouteError.LocationUnavailable()) }

        assertEquals(listOf<TrackingUiEvent>(TrackingUiEvent.ShowError(RouteUiError.LocationUnavailable)), events)
    }

    // endregion

    private companion object {
        const val STARTED_AT = 1_000_000L
        const val ENDED_AT = 2_000_000L
        const val SNAPSHOT_PATH = "/snapshots/activity.png"

        /** TrackingSessionManager reports a location issue after this many consecutive failures. */
        const val UNAVAILABLE_THRESHOLD = 3

        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        val NEXT = Coordinates(latitude = 52.001, longitude = 13.000)
        val PLANNED_ROUTE = listOf(
            Coordinates(latitude = 52.100, longitude = 13.100),
            Coordinates(latitude = 52.200, longitude = 13.200)
        )
        val PROFILE = UserProfile(weightKg = 70.0)
    }
}
