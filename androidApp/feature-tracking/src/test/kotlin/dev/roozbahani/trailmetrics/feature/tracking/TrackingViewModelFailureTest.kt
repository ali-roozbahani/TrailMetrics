package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.StoredUserProfileUnreadableException
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
import kotlin.test.assertIs
import kotlin.test.assertNull

/**
 * Persistence failures in [TrackingViewModel]: each one is shown as a general error and never
 * escapes viewModelScope (runTest fails a test when one does). Kept apart from
 * [TrackingViewModelTest] so neither class outgrows Detekt's LargeClass limit.
 */
class TrackingViewModelFailureTest {

    private lateinit var sessionManager: TrackingSessionManager

    private val testScheduler = TestCoroutineScheduler()

    private val locationRepository = FakeLocationRepository()
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

    /** A real TrackingSessionManager built from fakes, with a state subscriber kept for the whole test. */
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.createViewModel(): TrackingViewModel {
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
        val viewModel = TrackingViewModel(
            trackingSessionManager = sessionManager,
            userProfileRepository = userProfileRepository,
            calorieCalculator = CalorieCalculator(),
            saveActivityUseCase = SaveActivityUseCase(activityHistoryRepository, CalorieCalculator(), clock),
            activityType = ActivityType.Cycling,
            plannedRoutePoints = PLANNED_ROUTE,
            clock = clock
        )
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
        testScheduler.runCurrent()
        return viewModel
    }

    private fun startAndStop(viewModel: TrackingViewModel) {
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        sessionManager.stop()
        testScheduler.runCurrent()
    }

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

    @Test
    fun `a failing profile load at init emits a general ShowError and leaves calories null`() =
        runTest(testScheduler) {
            userProfileRepository.userProfile = PROFILE
            userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()

            viewModel.onAction(TrackingAction.Start(START))
            testScheduler.runCurrent()
            receiveLocation(NEXT, millisAfterStart = 60_000L)

            assertEquals(listOf<TrackingEvent>(TrackingEvent.ShowError(RouteUiError.General)), events)
            assertNull(viewModel.state.value.calories)
        }

    @Test
    fun `a Finish whose save throws emits a general ShowError, not Saved, and can be retried`() =
        runTest(testScheduler) {
            userProfileRepository.userProfile = PROFILE
            val viewModel = createViewModel()
            startAndStop(viewModel)
            val events = collectEvents(viewModel)
            activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")

            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(listOf<TrackingEvent>(TrackingEvent.ShowError(RouteUiError.General)), events)
            assertEquals(emptyList(), activityHistoryRepository.savedActivities)

            activityHistoryRepository.saveActivityFailure = null
            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(listOf(TrackingEvent.ShowError(RouteUiError.General), TrackingEvent.Saved), events)
            assertEquals(1, activityHistoryRepository.savedActivities.size)
        }

    @Test
    fun `a Finish without a loaded profile reads it again and saves once it is readable`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            startAndStop(viewModel)
            val events = collectEvents(viewModel)
            userProfileRepository.userProfile = PROFILE

            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(listOf<TrackingEvent>(TrackingEvent.Saved), events)
            assertEquals(1, activityHistoryRepository.savedActivities.size)
            assertEquals(2, userProfileRepository.getUserProfileCalls)
        }

    @Test
    fun `a Finish whose profile is still missing emits a general ShowError and keeps the session`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            startAndStop(viewModel)
            val events = collectEvents(viewModel)

            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(listOf<TrackingEvent>(TrackingEvent.ShowError(RouteUiError.General)), events)
            assertEquals(emptyList(), activityHistoryRepository.savedActivities)
            assertIs<TrackingState.Finished>(viewModel.state.value.trackingState)

            userProfileRepository.userProfile = PROFILE
            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(listOf(TrackingEvent.ShowError(RouteUiError.General), TrackingEvent.Saved), events)
            assertEquals(1, activityHistoryRepository.savedActivities.size)
        }

    @Test
    fun `a Finish whose profile read fails emits a general ShowError and can be retried`() =
        runTest(testScheduler) {
            userProfileRepository.userProfile = PROFILE
            userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            startAndStop(viewModel)

            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            // One error for the failed load at init, one for the failed read on Finish.
            assertEquals(List(2) { TrackingEvent.ShowError(RouteUiError.General) }, events)
            assertEquals(emptyList(), activityHistoryRepository.savedActivities)
            assertEquals(2, userProfileRepository.getUserProfileCalls)

            userProfileRepository.getUserProfileFailure = null
            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(TrackingEvent.Saved, events.last())
            assertEquals(1, activityHistoryRepository.savedActivities.size)
        }

    @Test
    fun `an unreadable stored profile is a failed profile read, at init and on Finish`() =
        runTest(testScheduler) {
            userProfileRepository.getUserProfileFailure = StoredUserProfileUnreadableException(cause = null)
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            startAndStop(viewModel)

            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(List(2) { TrackingEvent.ShowError(RouteUiError.General) }, events)
            assertNull(viewModel.state.value.calories)
            assertEquals(emptyList(), activityHistoryRepository.savedActivities)
            assertEquals(2, userProfileRepository.getUserProfileCalls)

            // The user saves a new profile elsewhere; the broken value is gone and Finish works.
            userProfileRepository.saveUserProfile(PROFILE)
            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()

            assertEquals(TrackingEvent.Saved, events.last())
            assertEquals(1, activityHistoryRepository.savedActivities.size)
        }

    @Test
    fun `Finish tapped twice while the profile is read again reads and saves once`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            startAndStop(viewModel)
            val events = collectEvents(viewModel)
            userProfileRepository.userProfile = PROFILE
            val profileGate = CompletableDeferred<Unit>()
            userProfileRepository.getUserProfileGate = profileGate

            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            viewModel.onAction(TrackingAction.Finish(SNAPSHOT_PATH))
            testScheduler.runCurrent()
            profileGate.complete(Unit)
            testScheduler.runCurrent()

            assertEquals(listOf<TrackingEvent>(TrackingEvent.Saved), events)
            assertEquals(1, activityHistoryRepository.savedActivities.size)
            assertEquals(2, userProfileRepository.getUserProfileCalls)
        }

    private companion object {
        const val STARTED_AT = 1_000_000L

        /** The monotonic clock at Start; deliberately unrelated to the wall-clock [STARTED_AT]. */
        const val START_ELAPSED_REALTIME = 5_000L
        const val SNAPSHOT_PATH = "/snapshots/activity.png"

        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        val NEXT = Coordinates(latitude = 52.001, longitude = 13.000)
        val PLANNED_ROUTE = listOf(
            Coordinates(latitude = 52.100, longitude = 13.100),
            Coordinates(latitude = 52.200, longitude = 13.200)
        )
        val PROFILE = UserProfile(weightKg = 70.0)
    }
}
