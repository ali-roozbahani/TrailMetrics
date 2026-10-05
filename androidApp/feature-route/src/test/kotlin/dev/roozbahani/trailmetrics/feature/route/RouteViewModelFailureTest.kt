package dev.roozbahani.trailmetrics.feature.route

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.feature.route.fakes.FakeDirectionsRepository
import kotlinx.coroutines.CancellationException
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
 * Persistence failures in [RouteViewModel]: each one is shown as a general error and never
 * escapes viewModelScope (runTest fails a test when one does), and cancellation is not shown
 * as an error. Kept apart from [RouteViewModelTest] so neither class outgrows Detekt's
 * LargeClass limit.
 */
class RouteViewModelFailureTest {

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
    private fun TestScope.collectEvents(viewModel: RouteViewModel): List<RouteEvent> {
        val events = mutableListOf<RouteEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        return events
    }

    private fun RouteViewModel.tapWaypoints(vararg coordinates: Coordinates) {
        coordinates.forEach { onAction(RouteAction.MapTapped(it)) }
    }

    @Test
    fun `a failing profile load at init emits a general ShowError and leaves the profile unset`() =
        runTest(testScheduler) {
            userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")

            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()

            assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.General)), events)
            assertEquals(RouteState(startPoint = START, userProfile = null), viewModel.state.value)
        }

    @Test
    fun `a failing profile save emits a general ShowError and keeps the previous profile`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        userProfileRepository.saveUserProfileFailure = IllegalStateException("disk full")

        viewModel.onAction(RouteAction.UserProfileSaved(72.5))
        testScheduler.runCurrent()

        assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.General)), events)
        assertEquals(emptyList(), userProfileRepository.savedProfiles)
        assertEquals(PROFILE, viewModel.state.value.userProfile)
    }

    @Test
    fun `a cancelled profile save emits no error and keeps the previous profile`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        userProfileRepository.saveUserProfileFailure = CancellationException("cancelled")

        viewModel.onAction(RouteAction.UserProfileSaved(72.5))
        testScheduler.runCurrent()

        assertEquals(emptyList(), events)
        assertEquals(PROFILE, viewModel.state.value.userProfile)
    }

    @Test
    fun `starting tracking when the profile load fails emits a general ShowError and does not navigate`() =
        runTest(testScheduler) {
            userProfileRepository.userProfile = PROFILE
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()
            viewModel.tapWaypoints(WP_A, WP_B, WP_C)
            viewModel.onAction(RouteAction.GenerateRouteClicked)
            testScheduler.runCurrent()
            userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")

            viewModel.onAction(RouteAction.StartTrackingClicked)
            testScheduler.runCurrent()

            assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.General)), events)
        }

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
    }
}
