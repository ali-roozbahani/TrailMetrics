package dev.roozbahani.trailmetrics.feature.route

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.StoredUserProfileUnreadableException
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.feature.route.fakes.FakeDirectionsRepository
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

/**
 * A stored profile that cannot be decoded ([StoredUserProfileUnreadableException]) is treated like a
 * missing one, so the user can enter a new profile, and is shown once as a general error.
 */
class RouteViewModelUnreadableProfileTest {

    private val testScheduler = TestCoroutineScheduler()

    private val locationRepository = FakeLocationRepository(Result.success(START))
    private val directionsRepository = FakeDirectionsRepository(Result.success(GENERATED_ROUTE))
    private val userProfileRepository = FakeUserProfileRepository().apply {
        getUserProfileFailure = StoredUserProfileUnreadableException(cause = null)
    }

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

    private fun RouteViewModel.generateRoute() {
        listOf(WP_A, WP_B, WP_C).forEach { onAction(RouteAction.MapTapped(it)) }
        onAction(RouteAction.GenerateRouteClicked)
    }

    @Test
    fun `an unreadable profile at load shows one general error and leaves the profile unset`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()

            assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.General)), events)
            assertEquals(null, viewModel.state.value.userProfile)
        }

    @Test
    fun `Start Tracking with an unreadable profile requests a new one without a second error`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()
            viewModel.generateRoute()
            testScheduler.runCurrent()
            events.clear()

            viewModel.onAction(RouteAction.StartTrackingClicked)
            testScheduler.runCurrent()

            assertEquals(listOf<RouteEvent>(RouteEvent.RequestUserProfile), events)
        }

    @Test
    fun `saving a profile after an unreadable one replaces it and Start Tracking navigates`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()
            viewModel.generateRoute()
            testScheduler.runCurrent()
            events.clear()

            viewModel.onAction(RouteAction.UserProfileSaved(72.5))
            viewModel.onAction(RouteAction.StartTrackingClicked)
            testScheduler.runCurrent()

            assertEquals(listOf(UserProfile(72.5)), userProfileRepository.savedProfiles)
            assertEquals(UserProfile(72.5), viewModel.state.value.userProfile)
            assertEquals(
                listOf<RouteEvent>(
                    RouteEvent.NavigateToTracking(
                        startPoint = START,
                        plannedRoutePoints = GENERATED_ROUTE.points.map { it.coordinates },
                        activityType = viewModel.state.value.selectedActivityType
                    )
                ),
                events
            )
        }

    @Test
    fun `a reset after saving a new profile shows no error`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.onAction(RouteAction.UserProfileSaved(72.5))
        testScheduler.runCurrent()
        events.clear()

        viewModel.onAction(RouteAction.ResetClicked)
        testScheduler.runCurrent()

        assertEquals(emptyList(), events)
        assertEquals(UserProfile(72.5), viewModel.state.value.userProfile)
    }

    private companion object {
        val START = Coordinates(latitude = 52.52, longitude = 13.405)
        val WP_A = Coordinates(latitude = 52.521, longitude = 13.406)
        val WP_B = Coordinates(latitude = 52.522, longitude = 13.407)
        val WP_C = Coordinates(latitude = 52.523, longitude = 13.408)
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
    }
}
