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
import kotlin.test.assertTrue

/**
 * The elapsed time the screen shows ticks between location events while Tracking, and stands still otherwise.
 * The monotonic [FakeClock] and the virtual time of [testScheduler] are moved together, with no location event.
 */
class TrackingViewModelElapsedTimeTest {

    private lateinit var sessionManager: TrackingSessionManager

    private val testScheduler = TestCoroutineScheduler()
    private val locationRepository = FakeLocationRepository()
    private val clock = FakeClock(nowMillis = 1_000_000L, elapsedRealtimeMillis = START_ELAPSED_REALTIME)

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
    private fun TestScope.createStartedViewModel(): TrackingViewModel {
        createSessionManager()
        val viewModel = newViewModel()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.displayedElapsedMillis.collect {} }
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        return viewModel
    }

    private fun TestScope.createSessionManager() {
        sessionManager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = FakeTrackingServiceLauncher(),
            speedCalculator = SpeedCalculator(),
            clock = clock,
            logger = FakeLogger(),
            trackingSessionStore = FakeTrackingSessionStore(),
            scope = backgroundScope
        )
    }

    /** A ViewModel on [sessionManager] as it is now (a screen opened again), with nothing collecting it yet. */
    private fun newViewModel(): TrackingViewModel =
        TrackingViewModel(
            trackingSessionManager = sessionManager,
            userProfileRepository = FakeUserProfileRepository(),
            trackingMetricsUseCase = TrackingMetricsUseCase(CalorieCalculator()),
            saveActivityUseCase = SaveActivityUseCase(FakeActivityHistoryRepository(), CalorieCalculator(), clock),
            activityType = ActivityType.Running,
            plannedRoutePoints = emptyList(),
            clock = clock,
            snapshotFileDeleter = FakeSnapshotFileDeleter()
        )

    /** The device's monotonic clock and the coroutines' virtual time both move by [millis]. */
    @OptIn(ExperimentalCoroutinesApi::class) // advanceTimeBy has no stable replacement
    private fun passTime(millis: Long) {
        clock.elapsedRealtimeMillis += millis
        testScheduler.advanceTimeBy(millis)
        testScheduler.runCurrent()
    }

    private fun TrackingViewModel.shownMillis(): Long = displayedElapsedMillis.value

    @Test
    fun `the shown time advances each second while tracking with no location event`() = runTest(testScheduler) {
        val viewModel = createStartedViewModel()
        assertIs<TrackingState.Tracking>(viewModel.state.value.trackingState)
        assertEquals(0L, viewModel.shownMillis())

        passTime(1_000L)
        assertEquals(1_000L, viewModel.shownMillis())

        passTime(1_000L)
        passTime(1_000L)
        assertEquals(3_000L, viewModel.shownMillis())
        // The recorded time is the domain's: unchanged without a location event.
        assertEquals(0L, viewModel.state.value.currentMetrics?.elapsedMillis)
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `a tick changes only the shown time, not the screen state`() = runTest(testScheduler) {
        val viewModel = createStartedViewModel()
        val screenStates = mutableListOf<TrackingScreenState>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect(screenStates::add) }
        val statesBeforeTicks = screenStates.size

        passTime(1_000L)
        passTime(1_000L)
        passTime(1_000L)

        assertEquals(3_000L, viewModel.shownMillis())
        // The whole screen recomposes on a new screen state; the ticks must not make one.
        assertEquals(statesBeforeTicks, screenStates.size)
    }

    @Test
    fun `a location event after ticking does not move the shown time back or forward`() = runTest(testScheduler) {
        val viewModel = createStartedViewModel()
        passTime(2_000L)
        assertEquals(2_000L, viewModel.shownMillis())

        locationRepository.emit(LocationUpdate.Success(NEXT, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.runCurrent()

        assertEquals(2_000L, viewModel.state.value.currentMetrics?.elapsedMillis)
        assertEquals(2_000L, viewModel.shownMillis())
    }

    @Test
    fun `the shown time stands still while paused and goes on from there after Resume`() = runTest(testScheduler) {
        val viewModel = createStartedViewModel()
        locationRepository.emit(LocationUpdate.Success(NEXT, speedMetersPerSecond = null, accuracyMeters = null))
        passTime(3_000L)
        locationRepository.emit(LocationUpdate.Success(START, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.runCurrent()
        assertEquals(3_000L, viewModel.shownMillis())

        viewModel.onAction(TrackingAction.Pause)
        testScheduler.runCurrent()
        assertIs<TrackingState.Paused>(viewModel.state.value.trackingState)

        passTime(5_000L)
        passTime(5_000L)
        assertEquals(3_000L, viewModel.shownMillis())

        viewModel.onAction(TrackingAction.Resume)
        testScheduler.runCurrent()
        assertEquals(3_000L, viewModel.shownMillis())

        passTime(1_000L)
        assertEquals(4_000L, viewModel.shownMillis())
    }

    @Test
    fun `the first read of the shown time on opening the screen is the session's time, not 0`() =
        runTest(testScheduler) {
            val first = createStartedViewModel()
            passTime(7_000L)
            first.onAction(TrackingAction.Pause)
            testScheduler.runCurrent()

            // Before anything collects it, so before the first tick.
            assertEquals(7_000L, newViewModel().displayedElapsedMillis.value)
        }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `the first read after a re-subscribe past the 5 s stop is not 0`() = runTest(testScheduler) {
        createSessionManager()
        val viewModel = newViewModel()
        val collector = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.displayedElapsedMillis.collect {}
        }
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        passTime(3_000L)
        collector.cancel()
        passTime(6_000L) // past WhileSubscribed's 5 s: the ticking stopped

        val reads = mutableListOf<Long>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.displayedElapsedMillis.collect(reads::add)
        }

        assertTrue(reads.first() > 0L, "first read after the re-subscribe: ${reads.first()}")
        assertEquals(9_000L, reads.last(), "then the time now")
    }

    private companion object {
        const val START_ELAPSED_REALTIME = 5_000L
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        val NEXT = Coordinates(latitude = 52.001, longitude = 13.000)
    }
}
