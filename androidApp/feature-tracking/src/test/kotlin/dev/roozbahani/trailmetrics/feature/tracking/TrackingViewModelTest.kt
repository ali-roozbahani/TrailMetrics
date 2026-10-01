package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.RouteError
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
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
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
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TrackingViewModelTest {

    private val testScheduler = TestCoroutineScheduler()

    private val locationRepository = FakeLocationRepository()
    private val trackingServiceLauncher = FakeTrackingServiceLauncher()
    private val clock = FakeClock(nowMillis = STARTED_AT, elapsedRealtimeMillis = START_ELAPSED_REALTIME)
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
     * state is stateIn(WhileSubscribed), so by default a subscriber is kept for the whole test;
     * with [observeState] false the test manages its own subscribers.
     */
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.createViewModel(
        plannedRoutePoints: List<Coordinates> = PLANNED_ROUTE,
        activityType: ActivityType = ActivityType.Cycling,
        observeState: Boolean = true
    ): TrackingViewModel {
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
            activityType = activityType,
            plannedRoutePoints = plannedRoutePoints,
            clock = clock
        )
        if (observeState) observeState(viewModel)
        testScheduler.runCurrent()
        return viewModel
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.observeState(viewModel: TrackingViewModel): Job =
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }

    private fun startAndStop(viewModel: TrackingViewModel) {
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()
    }

    private fun expectedCalories(activityType: ActivityType, metrics: TrackingMetrics): Double =
        CalorieCalculator().calculate(
            activityType = activityType,
            averageSpeedMetersPerSecond = assertNotNull(metrics.averageSpeedMetersPerSecond),
            weightKg = PROFILE.weightKg,
            durationMillis = metrics.elapsedMillis
        )

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.collectEvents(viewModel: TrackingViewModel): List<TrackingEvent> {
        val events = mutableListOf<TrackingEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        return events
    }

    private fun receiveLocation(coordinates: Coordinates, millisAfterStart: Long) {
        clock.elapsedRealtimeMillis = START_ELAPSED_REALTIME + millisAfterStart
        locationRepository.emit(LocationUpdate.Success(coordinates, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.runCurrent()
    }

    private fun receiveUnavailable(reason: RouteError) {
        locationRepository.emit(LocationUpdate.Unavailable(reason))
        testScheduler.runCurrent()
    }

    /** Returns how many times completion was signalled. */
    private fun TestScope.finish(viewModel: TrackingViewModel, snapshotFilePath: String?): Int {
        val events = collectEvents(viewModel)
        viewModel.onAction(TrackingAction.Finish(snapshotFilePath))
        testScheduler.runCurrent()
        return events.count { it == TrackingEvent.Saved }
    }

    // region state transitions

    @Test
    fun `initial state is Idle with no calories and only start enabled`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        val state = viewModel.state.value
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

            viewModel.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()

            val state = viewModel.state.value
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
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        receiveLocation(NEXT, millisAfterStart = 60_000L)

        val metrics = assertNotNull(viewModel.state.value.currentMetrics)
        assertEquals(listOf(START, NEXT), viewModel.state.value.currentPath)
        assertEquals(60_000L, metrics.elapsedMillis)
        assertTrue(metrics.distanceMeters > 0.0)
    }

    @Test
    fun `pause then resume moves Tracking to Paused and back to Tracking`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        viewModel.onAction(TrackingAction.Pause)
        testScheduler.runCurrent()
        assertIs<TrackingState.Paused>(viewModel.state.value.trackingState)
        assertTrue(viewModel.state.value.canResume)
        assertFalse(viewModel.state.value.canPause)
        assertTrue(viewModel.state.value.canStop)

        viewModel.onAction(TrackingAction.Resume)
        testScheduler.runCurrent()
        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
        assertTrue(viewModel.state.value.canPause)
    }

    @Test
    fun `stop while tracking finishes the session and stops the tracking service`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()

        val state = viewModel.state.value
        assertIs<TrackingState.Finished>(state.trackingState)
        assertNull(state.currentMetrics)
        assertTrue(state.canStart)
        assertFalse(state.canStop)
        assertEquals(1, trackingServiceLauncher.stopCalls)
    }

    @Test
    fun `stop while paused finishes the session`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Pause)
        testScheduler.runCurrent()

        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()

        assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)
    }

    @Test
    fun `granting location permission starts tracking at the given point`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        viewModel.onAction(TrackingAction.LocationPermissionGranted(START))
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
        assertEquals(listOf(START), viewModel.state.value.currentPath)
    }

    // endregion

    // region calories

    @Test
    fun `calories are null without a saved profile`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        receiveLocation(NEXT, millisAfterStart = 60_000L)

        assertNotNull(viewModel.state.value.currentMetrics?.averageSpeedMetersPerSecond)
        assertNull(viewModel.state.value.calories)
    }

    @Test
    fun `calories are null while the average speed is unknown`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()

        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        assertNull(viewModel.state.value.currentMetrics?.averageSpeedMetersPerSecond)
        assertNull(viewModel.state.value.calories)
    }

    @Test
    fun `calories are computed from the profile weight and the average speed`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        receiveLocation(NEXT, millisAfterStart = 60_000L)

        val metrics = assertNotNull(viewModel.state.value.currentMetrics)
        val expected = CalorieCalculator().calculate(
            activityType = ActivityType.Cycling,
            averageSpeedMetersPerSecond = assertNotNull(metrics.averageSpeedMetersPerSecond),
            weightKg = PROFILE.weightKg,
            durationMillis = metrics.elapsedMillis
        )
        assertEquals(expected, viewModel.state.value.calories)
    }

    @Test
    fun `calories are kept while paused and dropped once finished`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(NEXT, millisAfterStart = 60_000L)
        val trackingCalories = assertNotNull(viewModel.state.value.calories)

        viewModel.onAction(TrackingAction.Pause)
        testScheduler.runCurrent()
        assertEquals(trackingCalories, viewModel.state.value.calories)

        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()
        assertNull(viewModel.state.value.calories)
    }

    @Test
    fun `calories are recomputed whenever the metrics change`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(NEXT, millisAfterStart = 60_000L)
        val firstCalories = assertNotNull(viewModel.state.value.calories)

        receiveLocation(END, millisAfterStart = 120_000L)

        val metrics = assertNotNull(viewModel.state.value.currentMetrics)
        assertEquals(120_000L, metrics.elapsedMillis)
        assertEquals(expectedCalories(ActivityType.Cycling, metrics), viewModel.state.value.calories)
        assertNotEquals(firstCalories, viewModel.state.value.calories)
    }

    @Test
    fun `calories appear once a profile that loads after tracking started arrives`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val profileGate = CompletableDeferred<Unit>()
        userProfileRepository.getUserProfileGate = profileGate
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(NEXT, millisAfterStart = 60_000L)
        assertNull(viewModel.state.value.calories)

        profileGate.complete(Unit)
        testScheduler.runCurrent()

        val metrics = assertNotNull(viewModel.state.value.currentMetrics)
        assertEquals(expectedCalories(ActivityType.Cycling, metrics), viewModel.state.value.calories)
    }

    @Test
    fun `calories use the activity type the screen was opened with`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel(activityType = ActivityType.Running)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        receiveLocation(NEXT, millisAfterStart = 60_000L)

        val metrics = assertNotNull(viewModel.state.value.currentMetrics)
        val runningCalories = expectedCalories(ActivityType.Running, metrics)
        assertNotEquals(expectedCalories(ActivityType.Cycling, metrics), runningCalories)
        assertEquals(runningCalories, viewModel.state.value.calories)
    }

    // endregion

    // region start time

    @Test
    fun `granting location permission records the wall-clock start time`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.LocationPermissionGranted(START))
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()

        finish(viewModel, SNAPSHOT_PATH)

        assertEquals(STARTED_AT, activityHistoryRepository.savedActivities.single().startedAtEpochMillis)
    }

    @Test
    fun `a second Start overwrites the recorded start time`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        startAndStop(viewModel)
        clock.nowMillis = RESTARTED_AT
        startAndStop(viewModel)

        finish(viewModel, SNAPSHOT_PATH)

        assertEquals(RESTARTED_AT, activityHistoryRepository.savedActivities.single().startedAtEpochMillis)
    }

    // endregion

    // region finish

    @Test
    fun `finish saves the activity with the start time from Start and signals once`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(NEXT, millisAfterStart = 60_000L)
        clock.nowMillis = ENDED_AT
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()
        val finished = assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)

        val savedSignals = finish(viewModel, SNAPSHOT_PATH)

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
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()

        val savedSignals = finish(viewModel, snapshotFilePath = null)

        assertEquals(1, savedSignals)
        assertNull(activityHistoryRepository.savedActivities.single().snapshotFilePath)
    }

    @Test
    fun `finish before the session is finished saves nothing and does not signal`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        val savedSignals = finish(viewModel, SNAPSHOT_PATH)

        assertEquals(0, savedSignals)
        assertEquals(emptyList(), activityHistoryRepository.savedActivities)
    }

    @Test
    fun `finish without a saved profile saves nothing and does not signal`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()

        val savedSignals = finish(viewModel, SNAPSHOT_PATH)

        assertEquals(0, savedSignals)
        assertEquals(emptyList(), activityHistoryRepository.savedActivities)
    }

    @Test
    fun `finish saves calories computed from the profile weight and the activity type`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel(activityType = ActivityType.Walking)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(NEXT, millisAfterStart = 60_000L)
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()
        val finished = assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)

        finish(viewModel, SNAPSHOT_PATH)

        val record = activityHistoryRepository.savedActivities.single()
        assertEquals(ActivityType.Walking, record.activityType)
        assertEquals(expectedCalories(ActivityType.Walking, finished.metrics), record.calories)
    }

    @Test
    fun `finishing twice currently saves the activity twice`() = runTest(testScheduler) {
        // Pins tracking-finish-saves-twice (BOARD.md): nothing guards against a repeated Finish.
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        startAndStop(viewModel)
        val events = collectEvents(viewModel)

        repeat(2) {
            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()
        }

        assertEquals(List(2) { TrackingEvent.Saved }, events)
        assertEquals(2, activityHistoryRepository.savedActivities.size)
    }

    @Test
    fun `Saved is buffered until a collector subscribes`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        startAndStop(viewModel)
        viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
        testScheduler.runCurrent()
        assertEquals(1, activityHistoryRepository.savedActivities.size)

        val events = collectEvents(viewModel)
        testScheduler.runCurrent()

        assertEquals(listOf<TrackingEvent>(TrackingEvent.Saved), events)
    }

    // endregion

    // region location issues

    @Test
    fun `missing location permission is mapped to RequestLocationPermission`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        repeat(UNAVAILABLE_THRESHOLD) { receiveUnavailable(RouteError.MissingLocationPermission()) }

        assertEquals(listOf<TrackingEvent>(TrackingEvent.RequestLocationPermission), events)
    }

    @Test
    fun `other location errors are mapped to ShowError`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        repeat(UNAVAILABLE_THRESHOLD) { receiveUnavailable(RouteError.LocationUnavailable()) }

        assertEquals(listOf<TrackingEvent>(TrackingEvent.ShowError(RouteUiError.LocationUnavailable)), events)
    }

    @Test
    fun `a location error with no specific UI error is shown as a general error`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        repeat(UNAVAILABLE_THRESHOLD) { receiveUnavailable(RouteError.DirectionsApiError(IllegalStateException())) }

        assertEquals(listOf<TrackingEvent>(TrackingEvent.ShowError(RouteUiError.General)), events)
    }

    @Test
    fun `location issues raised while nobody collects events are dropped`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        repeat(UNAVAILABLE_THRESHOLD) { receiveUnavailable(RouteError.MissingLocationPermission()) }

        val events = collectEvents(viewModel)
        testScheduler.runCurrent()

        assertEquals(emptyList(), events)
    }

    // endregion

    // region state sharing

    @OptIn(ExperimentalCoroutinesApi::class) // advanceTimeBy has no stable replacement
    @Test
    fun `state keeps following the session for five seconds after the last subscriber leaves`() =
        runTest(testScheduler) {
            val viewModel = createViewModel(observeState = false)
            val subscriber = observeState(viewModel)
            viewModel.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()
            subscriber.cancel()

            testScheduler.advanceTimeBy(STATE_STOP_TIMEOUT_MILLIS - 1)
            testScheduler.runCurrent()
            viewModel.onAction(TrackingAction.Pause)
            testScheduler.runCurrent()

            assertIs<TrackingState.Paused>(viewModel.state.value.trackingState)
        }

    @OptIn(ExperimentalCoroutinesApi::class) // advanceTimeBy has no stable replacement
    @Test
    fun `state stops following the session five seconds after the last subscriber leaves`() =
        runTest(testScheduler) {
            val viewModel = createViewModel(observeState = false)
            val subscriber = observeState(viewModel)
            viewModel.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()
            subscriber.cancel()

            testScheduler.advanceTimeBy(STATE_STOP_TIMEOUT_MILLIS)
            testScheduler.runCurrent()
            viewModel.onAction(TrackingAction.Pause)
            testScheduler.runCurrent()

            assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
        }

    // endregion

    // region route progress and completion (moved here from TrackingScreen)

    @Test
    fun `the planned route is exposed in state`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        assertEquals(PLANNED_ROUTE, viewModel.state.value.plannedRoutePoints)
        assertNull(viewModel.state.value.routeProgress)
        assertFalse(viewModel.state.value.hasReachedDestination)
    }

    @Test
    fun `the planned route stays in state while tracking paused and finished`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val plannedRouteByState = mutableListOf<List<Coordinates>>()

        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        plannedRouteByState += viewModel.state.value.plannedRoutePoints
        viewModel.onAction(TrackingAction.Pause)
        testScheduler.runCurrent()
        plannedRouteByState += viewModel.state.value.plannedRoutePoints
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()
        plannedRouteByState += viewModel.state.value.plannedRoutePoints

        assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)
        assertEquals(List(3) { PLANNED_ROUTE }, plannedRouteByState)
    }

    @Test
    fun `route progress follows location updates`() = runTest(testScheduler) {
        val viewModel = createViewModel(plannedRoutePoints = WALKED_ROUTE)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        assertEquals(0, assertNotNull(viewModel.state.value.routeProgress).lastIndex)

        receiveLocation(NEXT, millisAfterStart = 60_000L)

        val progress = assertNotNull(viewModel.state.value.routeProgress)
        assertEquals(1, progress.lastIndex)
        assertEquals(listOf(START, NEXT), progress.traveledSegment)
        assertFalse(viewModel.state.value.hasReachedDestination)
        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
    }

    @Test
    fun `reaching the end of the planned route stops tracking and keeps the progress`() = runTest(testScheduler) {
        val viewModel = createViewModel(plannedRoutePoints = WALKED_ROUTE)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(NEXT, millisAfterStart = 60_000L)

        receiveLocation(END, millisAfterStart = 120_000L)

        val state = viewModel.state.value
        assertIs<TrackingState.Finished>(state.trackingState)
        assertTrue(state.hasReachedDestination)
        assertEquals(WALKED_ROUTE, assertNotNull(state.routeProgress).traveledSegment)
        assertEquals(1, trackingServiceLauncher.stopCalls)
    }

    @Test
    fun `reaching the end again in a later session does not stop a second time`() = runTest(testScheduler) {
        val viewModel = createViewModel(plannedRoutePoints = WALKED_ROUTE)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(END, millisAfterStart = 60_000L)
        assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)

        viewModel.onAction(TrackingAction.Start(END))
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
        assertEquals(1, trackingServiceLauncher.stopCalls)
    }

    @Test
    fun `a session stopped at the route end can be finished and saved`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel(plannedRoutePoints = WALKED_ROUTE)
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        receiveLocation(END, millisAfterStart = 60_000L)

        val savedSignals = finish(viewModel, SNAPSHOT_PATH)

        assertEquals(1, savedSignals)
        assertEquals(listOf(START, END), activityHistoryRepository.savedActivities.single().actualPath)
    }

    // endregion

    private companion object {
        const val STARTED_AT = 1_000_000L
        const val ENDED_AT = 2_000_000L
        const val RESTARTED_AT = 1_500_000L

        /** TrackingViewModel.state's SharingStarted.WhileSubscribed stop timeout. */
        const val STATE_STOP_TIMEOUT_MILLIS = 5_000L

        /** The monotonic clock at Start; deliberately unrelated to the wall-clock [STARTED_AT]. */
        const val START_ELAPSED_REALTIME = 5_000L
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

        /** A short planned route starting at [START]; its end is [END], ~222 m away. */
        val END = Coordinates(latitude = 52.002, longitude = 13.000)
        val WALKED_ROUTE = listOf(START, NEXT, END)
    }
}
