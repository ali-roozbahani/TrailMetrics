package dev.roozbahani.trailmetrics.feature.route

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.feature.route.fakes.FakeDirectionsRepository
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
import kotlin.test.assertNull

/**
 * A repeated `StartTrackingClicked` while one is still reading the profile: the in-flight one is
 * the only one that sends an event, and a later, separate tap works again whichever way the
 * earlier one ended. Kept apart from [RouteViewModelTest] so neither class outgrows Detekt's
 * LargeClass limit.
 */
class RouteViewModelRepeatedStartTrackingTest {

    private val testScheduler = TestCoroutineScheduler()

    private val locationRepository = FakeLocationRepository(Result.success(START))
    private val directionsRepository = FakeDirectionsRepository(Result.success(GENERATED_ROUTE))
    private val userProfileRepository = FakeUserProfileRepository()

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

    private fun createViewModel() = RouteViewModel(
        getCurrentLocationUseCase = GetCurrentLocationUseCase(locationRepository),
        generateClosedRouteUseCase = GenerateClosedRouteUseCase(directionsRepository),
        userProfileRepository = userProfileRepository
    )

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.collectEvents(viewModel: RouteViewModel): MutableList<RouteEvent> {
        val events = mutableListOf<RouteEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        return events
    }

    /** Lets init finish (its profile read included), taps three waypoints and generates the route. */
    private fun RouteViewModel.generate() {
        testScheduler.runCurrent()
        listOf(WP_A, WP_B, WP_C).forEach { onAction(RouteAction.MapTapped(it)) }
        onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
    }

    /** Holds the next profile reads until the returned gate is completed. */
    private fun holdProfileReads(): CompletableDeferred<Unit> =
        CompletableDeferred<Unit>().also { userProfileRepository.getUserProfileGate = it }

    private fun releaseProfileReads(gate: CompletableDeferred<Unit>) {
        gate.complete(Unit)
        userProfileRepository.getUserProfileGate = null
        testScheduler.runCurrent()
    }

    private fun RouteViewModel.tapStartTracking() {
        onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()
    }

    // region a repeated tap while one is in flight

    @Test
    fun `two Start tracking taps before the profile read returns navigate once`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.generate()
        val gate = holdProfileReads()

        viewModel.tapStartTracking()
        viewModel.tapStartTracking()
        assertEquals(emptyList(), events)
        releaseProfileReads(gate)

        assertEquals(1, events.count { it is RouteEvent.NavigateToTracking })
        assertEquals(listOf<RouteEvent>(NAVIGATE), events)
    }

    @Test
    fun `two Start tracking taps without a saved profile before the read returns request a profile once`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            viewModel.generate()
            val gate = holdProfileReads()

            viewModel.tapStartTracking()
            viewModel.tapStartTracking()
            releaseProfileReads(gate)

            assertEquals(1, events.count { it == RouteEvent.RequestUserProfile })
            assertEquals(listOf<RouteEvent>(RouteEvent.RequestUserProfile), events)
        }

    // endregion

    // region a later, separate tap

    @Test
    fun `a Start tracking tap after the previous one navigated navigates again`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.generate()

        viewModel.tapStartTracking()
        viewModel.tapStartTracking()

        assertEquals(listOf<RouteEvent>(NAVIGATE, NAVIGATE), events)
    }

    @Test
    fun `a Start tracking tap after the previous one requested a profile requests it again`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            viewModel.generate()

            viewModel.tapStartTracking()
            viewModel.tapStartTracking()

            assertEquals(listOf<RouteEvent>(RouteEvent.RequestUserProfile, RouteEvent.RequestUserProfile), events)
        }

    // endregion

    // region the guard is released on every exit

    @Test
    fun `a Start tracking tap after a failed profile read navigates`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        viewModel.generate()
        userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")
        viewModel.tapStartTracking()
        assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.General)), events)

        userProfileRepository.getUserProfileFailure = null
        viewModel.tapStartTracking()

        assertEquals(listOf(RouteEvent.ShowError(RouteUiError.General), NAVIGATE), events)
    }

    @Test
    fun `a Start tracking tap after one that found no route navigates once a route exists`() =
        runTest(testScheduler) {
            userProfileRepository.userProfile = PROFILE
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()
            viewModel.tapStartTracking()
            assertEquals(emptyList(), events)

            viewModel.generate()
            viewModel.tapStartTracking()

            assertEquals(listOf<RouteEvent>(NAVIGATE), events)
        }

    @Test
    fun `a Start tracking tap after a reset cleared the route during the profile read navigates`() =
        runTest(testScheduler) {
            userProfileRepository.userProfile = PROFILE
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            viewModel.generate()
            val gate = holdProfileReads()
            viewModel.tapStartTracking()
            locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())
            viewModel.onAction(RouteAction.ResetClicked)
            testScheduler.runCurrent()
            assertNull(viewModel.state.value.startPoint)
            releaseProfileReads(gate)
            val eventsBefore = events.size

            locationRepository.currentLocationResult = Result.success(START)
            viewModel.onAction(RouteAction.LocationPermissionGranted)
            viewModel.generate()
            viewModel.tapStartTracking()

            assertEquals(listOf<RouteEvent>(NAVIGATE), events.drop(eventsBefore))
        }

    // endregion

    private companion object {
        val START = Coordinates(latitude = 52.52, longitude = 13.405)
        val WP_A = Coordinates(latitude = 52.521, longitude = 13.406)
        val WP_B = Coordinates(latitude = 52.522, longitude = 13.407)
        val WP_C = Coordinates(latitude = 52.523, longitude = 13.408)
        val PROFILE = UserProfile(weightKg = 70.0)
        val GENERATED_ROUTE = Route(
            points = listOf(
                RoutePoint(START, 0),
                RoutePoint(WP_A, 1),
                RoutePoint(WP_B, 2),
                RoutePoint(WP_C, 3),
                RoutePoint(START, 4)
            ),
            distanceMeters = 1234.0
        )
        val NAVIGATE = RouteEvent.NavigateToTracking(
            startPoint = START,
            plannedRoutePoints = GENERATED_ROUTE.points.map { it.coordinates },
            activityType = ActivityType.Running
        )
    }
}
