package dev.roozbahani.trailmetrics

import dev.roozbahani.trailmetrics.core.navigation.AppRoute
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.fakes.FakeClock
import dev.roozbahani.trailmetrics.fakes.FakeLogger
import dev.roozbahani.trailmetrics.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.fakes.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.feature.route.RouteState
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
import kotlin.test.assertNull

/** [SavedSessionOfferViewModel] over a stored session: what it offers, and that it offers it once. */
class SavedSessionOfferViewModelTest {

    private val testScheduler = TestCoroutineScheduler()
    private val store = FakeTrackingSessionStore()
    private val logger = FakeLogger()

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

    private fun TestScope.createViewModel() = SavedSessionOfferViewModel(
        trackingSessionManager = TrackingSessionManager(
            locationRepository = FakeLocationRepository(),
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = FakeTrackingServiceLauncher(),
            speedCalculator = SpeedCalculator(),
            clock = FakeClock(),
            logger = FakeLogger(),
            trackingSessionStore = store,
            scope = backgroundScope
        ),
        logger = logger
    ).also { testScheduler.runCurrent() }

    private fun storeSession(state: TrackingState, activityType: ActivityType? = ActivityType.Cycling) {
        store.stored = state
        store.storedActivityType = activityType
        store.storedStartedAtEpochMillis = STARTED_AT
    }

    @Test
    fun `a stored Paused session is offered with its first point and stored type`() = runTest(testScheduler) {
        storeSession(TrackingState.Paused(METRICS))

        val viewModel = createViewModel()

        assertEquals(
            AppRoute.Tracking(FIRST_POINT, emptyList(), ActivityType.Cycling),
            viewModel.state.value.offer
        )
    }

    @Test
    fun `a stored Finished session is offered`() = runTest(testScheduler) {
        storeSession(TrackingState.Finished(METRICS), ActivityType.Walking)

        val viewModel = createViewModel()

        assertEquals(
            AppRoute.Tracking(FIRST_POINT, emptyList(), ActivityType.Walking),
            viewModel.state.value.offer
        )
    }

    @Test
    fun `a stored Tracking session is offered as the Paused session it is restored to`() = runTest(testScheduler) {
        storeSession(TrackingState.Tracking(METRICS))

        val viewModel = createViewModel()

        assertEquals(
            AppRoute.Tracking(FIRST_POINT, emptyList(), ActivityType.Cycling),
            viewModel.state.value.offer
        )
    }

    @Test
    fun `nothing is offered when no session is stored`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        assertNull(viewModel.state.value.offer)
        assertEquals(1, store.loadCalls)
    }

    @Test
    fun `nothing is offered for a session with an empty path`() = runTest(testScheduler) {
        storeSession(TrackingState.Paused(METRICS.copy(path = emptyList())))

        val viewModel = createViewModel()

        assertNull(viewModel.state.value.offer)
    }

    @Test
    fun `a session stored without a type is offered with the route screen's default type`() = runTest(testScheduler) {
        storeSession(TrackingState.Paused(METRICS), activityType = null)

        val viewModel = createViewModel()

        assertEquals(RouteState().selectedActivityType, viewModel.state.value.offer?.selectedActivityType)
    }

    @Test
    fun `the offer is gone after OfferConsumed and is not offered again`() = runTest(testScheduler) {
        storeSession(TrackingState.Paused(METRICS))
        val viewModel = createViewModel()

        viewModel.onAction(SavedSessionOfferAction.OfferConsumed)
        testScheduler.runCurrent()

        assertNull(viewModel.state.value.offer)
        assertEquals(1, store.loadCalls)
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `a failing restore offers nothing, is logged and emits RestoreFailed`() = runTest(testScheduler) {
        store.loadFailure = IllegalStateException("unreadable")

        val viewModel = createViewModel()
        val events = mutableListOf<SavedSessionOfferEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        testScheduler.runCurrent()

        assertNull(viewModel.state.value.offer)
        assertEquals(1, logger.messages.size)
        assertEquals(listOf<SavedSessionOfferEvent>(SavedSessionOfferEvent.RestoreFailed), events)
    }

    private companion object {
        const val STARTED_AT = 1_000L
        val FIRST_POINT = Coordinates(47.0, 8.0)
        val METRICS = TrackingMetrics(
            elapsedMillis = 60_000L,
            lastUpdateElapsedRealtimeMillis = 5_000L,
            distanceMeters = 150.0,
            path = listOf(FIRST_POINT, Coordinates(47.001, 8.001))
        )
    }
}
