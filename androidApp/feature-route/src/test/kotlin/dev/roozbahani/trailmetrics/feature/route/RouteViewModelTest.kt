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
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RouteViewModelTest {

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

    // region init

    @Test
    fun `init loads the current location and the saved user profile`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE

        val viewModel = createViewModel()
        testScheduler.runCurrent()

        assertEquals(RouteState(startPoint = START, userProfile = PROFILE), viewModel.state.value)
        assertEquals(1, locationRepository.getCurrentLocationCalls)
        assertEquals(1, userProfileRepository.getUserProfileCalls)
    }

    @Test
    fun `missing location permission emits ShowError then RequestLocationPermission in that order`() =
        runTest(testScheduler) {
            locationRepository.currentLocationResult = Result.failure(RouteError.MissingLocationPermission())

            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()

            assertEquals(
                listOf(
                    RouteEvent.ShowError(RouteUiError.MissingLocationPermission),
                    RouteEvent.RequestLocationPermission
                ),
                events
            )
            assertNull(viewModel.state.value.startPoint)
        }

    @Test
    fun `unavailable location emits only ShowError`() = runTest(testScheduler) {
        locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())

        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()

        assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.LocationUnavailable)), events)
        assertNull(viewModel.state.value.startPoint)
    }

    @Test
    fun `granting location permission reloads the current location`() = runTest(testScheduler) {
        locationRepository.currentLocationResult = Result.failure(RouteError.MissingLocationPermission())
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        locationRepository.currentLocationResult = Result.success(START)

        viewModel.onAction(RouteAction.LocationPermissionGranted)
        testScheduler.runCurrent()

        assertEquals(START, viewModel.state.value.startPoint)
        assertEquals(2, locationRepository.getCurrentLocationCalls)
    }

    @Test
    fun `granting location permission after a failed load does not repeat the error events`() =
        runTest(testScheduler) {
            locationRepository.currentLocationResult = Result.failure(RouteError.MissingLocationPermission())
            val viewModel = createViewModel()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()
            locationRepository.currentLocationResult = Result.success(START)

            viewModel.onAction(RouteAction.LocationPermissionGranted)
            testScheduler.runCurrent()

            assertEquals(
                listOf(
                    RouteEvent.ShowError(RouteUiError.MissingLocationPermission),
                    RouteEvent.RequestLocationPermission
                ),
                events
            )
        }

    // endregion

    // region waypoints

    @Test
    fun `tapping the map appends waypoints numbered in tap order`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        viewModel.tapWaypoints(WP_A, WP_B, WP_C)

        assertEquals(
            listOf(RoutePoint(WP_A, 0), RoutePoint(WP_B, 1), RoutePoint(WP_C, 2)),
            viewModel.state.value.waypoints
        )
    }

    @Test
    fun `removing a waypoint renumbers the remaining waypoints in order`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C, WP_D)

        viewModel.onAction(RouteAction.WaypointRemoved(RoutePoint(WP_B, 1)))

        assertEquals(
            listOf(RoutePoint(WP_A, 0), RoutePoint(WP_C, 1), RoutePoint(WP_D, 2)),
            viewModel.state.value.waypoints
        )
    }

    @Test
    fun `removing a waypoint clears the generated route`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C, WP_D)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        assertEquals(GENERATED_ROUTE, viewModel.state.value.generatedRoute)

        viewModel.onAction(RouteAction.WaypointRemoved(RoutePoint(WP_D, 3)))

        assertNull(viewModel.state.value.generatedRoute)
    }

    @Test
    fun `canGenerateRoute requires a start point and at least three waypoints`() = runTest(testScheduler) {
        locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        assertFalse(viewModel.state.value.canGenerateRoute, "no start point")

        locationRepository.currentLocationResult = Result.success(START)
        viewModel.onAction(RouteAction.LocationPermissionGranted)
        testScheduler.runCurrent()
        viewModel.onAction(RouteAction.WaypointRemoved(RoutePoint(WP_C, 2)))
        assertFalse(viewModel.state.value.canGenerateRoute, "two waypoints")

        viewModel.onAction(RouteAction.MapTapped(WP_C))
        assertTrue(viewModel.state.value.canGenerateRoute, "three waypoints")
    }

    @Test
    fun `removing a waypoint that is not in the list keeps the waypoints but clears the generated route`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            testScheduler.runCurrent()
            viewModel.tapWaypoints(WP_A, WP_B, WP_C)
            viewModel.onAction(RouteAction.GenerateRouteClicked)
            testScheduler.runCurrent()

            viewModel.onAction(RouteAction.WaypointRemoved(RoutePoint(WP_D, 3)))

            assertEquals(
                listOf(RoutePoint(WP_A, 0), RoutePoint(WP_B, 1), RoutePoint(WP_C, 2)),
                viewModel.state.value.waypoints
            )
            assertNull(viewModel.state.value.generatedRoute)
        }

    @Test
    fun `tapping the map after generating currently keeps the stale generated route`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.MapTapped(WP_D))

        assertEquals(4, viewModel.state.value.waypoints.size)
        assertEquals(GENERATED_ROUTE, viewModel.state.value.generatedRoute)
    }

    // endregion

    // region generate

    @Test
    fun `generating a route shows loading then stores the route`() = runTest(testScheduler) {
        val gate = CompletableDeferred<Unit>()
        directionsRepository.gate = gate
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)

        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        assertTrue(viewModel.state.value.isLoading)
        assertFalse(viewModel.state.value.canGenerateRoute, "not while loading")
        assertEquals(listOf(START to listOf(WP_A, WP_B, WP_C)), directionsRepository.requests)

        gate.complete(Unit)
        testScheduler.runCurrent()

        assertFalse(viewModel.state.value.isLoading)
        assertEquals(GENERATED_ROUTE, viewModel.state.value.generatedRoute)
    }

    @Test
    fun `route generation failure stops loading and emits ShowError`() = runTest(testScheduler) {
        directionsRepository.closedRouteResult =
            Result.failure(RouteError.DirectionsApiError(IllegalStateException("boom")))
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)

        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        assertFalse(viewModel.state.value.isLoading)
        assertNull(viewModel.state.value.generatedRoute)
        assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.General)), events)
    }

    @Test
    fun `generating with too few waypoints emits ShowError without calling directions`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B)

        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        assertFalse(viewModel.state.value.isLoading)
        assertTrue(directionsRepository.requests.isEmpty())
        assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.General)), events)
    }

    @Test
    fun `generating without a start point does nothing`() = runTest(testScheduler) {
        locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)

        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        assertFalse(viewModel.state.value.isLoading)
        assertTrue(directionsRepository.requests.isEmpty())
        // Only the init location error; the generate click itself emits nothing.
        assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(RouteUiError.LocationUnavailable)), events)
    }

    @Test
    fun `route generation failure maps each RouteError to its RouteUiError and stops loading`() =
        runTest(testScheduler) {
            val expected = listOf(
                RouteError.LocationUnavailable() to RouteUiError.LocationUnavailable,
                RouteError.MissingLocationPermission() to RouteUiError.MissingLocationPermission,
                RouteError.DirectionsApiError(IllegalStateException("boom")) to RouteUiError.General,
                RouteError.InsufficientWaypoints(required = 3, actual = 1) to RouteUiError.General
            )

            expected.forEach { (error, uiError) ->
                directionsRepository.closedRouteResult = Result.failure(error)
                val viewModel = createViewModel()
                val events = collectEvents(viewModel)
                testScheduler.runCurrent()
                viewModel.tapWaypoints(WP_A, WP_B, WP_C)

                viewModel.onAction(RouteAction.GenerateRouteClicked)
                testScheduler.runCurrent()

                assertEquals(listOf<RouteEvent>(RouteEvent.ShowError(uiError)), events, "$error")
                assertFalse(viewModel.state.value.isLoading, "$error")
            }
        }

    @Test
    fun `generating again after a failure stores the route`() = runTest(testScheduler) {
        directionsRepository.closedRouteResult = Result.failure(RouteError.DirectionsApiError(IllegalStateException()))
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        directionsRepository.closedRouteResult = Result.success(GENERATED_ROUTE)

        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        assertEquals(GENERATED_ROUTE, viewModel.state.value.generatedRoute)
        assertFalse(viewModel.state.value.isLoading)
    }

    /** Starts two generations; the first waits on the returned first gate, the second on the second. */
    private fun RouteViewModel.generateTwiceInFlight(): Pair<CompletableDeferred<Unit>, CompletableDeferred<Unit>> {
        val firstGate = CompletableDeferred<Unit>()
        val secondGate = CompletableDeferred<Unit>()
        testScheduler.runCurrent()
        tapWaypoints(WP_A, WP_B, WP_C)
        directionsRepository.gate = firstGate
        onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        directionsRepository.gate = secondGate
        onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        return firstGate to secondGate
    }

    @Test
    fun `a second generate while the first is in flight currently calls directions again`() = runTest(testScheduler) {
        val viewModel = createViewModel()

        viewModel.generateTwiceInFlight()

        assertEquals(
            listOf(START to listOf(WP_A, WP_B, WP_C), START to listOf(WP_A, WP_B, WP_C)),
            directionsRepository.requests
        )
    }

    @Test
    fun `with two generations in flight loading currently stops when the first of them finishes`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()
            val (_, secondGate) = viewModel.generateTwiceInFlight()

            secondGate.complete(Unit)
            testScheduler.runCurrent()

            assertFalse(viewModel.state.value.isLoading)
        }

    @Test
    fun `with two generations in flight the result that finishes last currently wins`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val (firstGate, secondGate) = viewModel.generateTwiceInFlight()
        directionsRepository.closedRouteResult = Result.success(OTHER_ROUTE)
        secondGate.complete(Unit)
        testScheduler.runCurrent()
        assertEquals(OTHER_ROUTE, viewModel.state.value.generatedRoute)
        directionsRepository.closedRouteResult = Result.success(GENERATED_ROUTE)

        firstGate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(GENERATED_ROUTE, viewModel.state.value.generatedRoute)
    }

    @Test
    fun `removing a waypoint while generating currently lets the stale result land`() = runTest(testScheduler) {
        val gate = CompletableDeferred<Unit>()
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C, WP_D)
        directionsRepository.gate = gate
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.WaypointRemoved(RoutePoint(WP_D, 3)))
        assertNull(viewModel.state.value.generatedRoute)
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(3, viewModel.state.value.waypoints.size)
        assertEquals(GENERATED_ROUTE, viewModel.state.value.generatedRoute)
        assertEquals(listOf(START to listOf(WP_A, WP_B, WP_C, WP_D)), directionsRepository.requests)
    }

    @Test
    fun `reset while generating currently lets the stale result land in the reset state`() = runTest(testScheduler) {
        val gate = CompletableDeferred<Unit>()
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        directionsRepository.gate = gate
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.ResetClicked)
        testScheduler.runCurrent()
        assertEquals(RouteState(startPoint = START), viewModel.state.value)
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(RouteState(startPoint = START, generatedRoute = GENERATED_ROUTE), viewModel.state.value)
    }

    // endregion

    // region activity type and profile

    @Test
    fun `selecting an activity type updates the state`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        assertEquals(ActivityType.Running, viewModel.state.value.selectedActivityType)

        viewModel.onAction(RouteAction.ActivityTypeSelected(ActivityType.Cycling))

        assertEquals(ActivityType.Cycling, viewModel.state.value.selectedActivityType)
    }

    @Test
    fun `saving the user profile persists it and updates the state`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.UserProfileSaved(72.5))
        testScheduler.runCurrent()

        assertEquals(listOf(UserProfile(72.5)), userProfileRepository.savedProfiles)
        assertEquals(UserProfile(72.5), viewModel.state.value.userProfile)
    }

    @Test
    fun `saving the user profile twice keeps the last weight`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.UserProfileSaved(72.5))
        viewModel.onAction(RouteAction.UserProfileSaved(68.25))
        testScheduler.runCurrent()

        assertEquals(listOf(UserProfile(72.5), UserProfile(68.25)), userProfileRepository.savedProfiles)
        assertEquals(UserProfile(68.25), userProfileRepository.userProfile)
        assertEquals(UserProfile(68.25), viewModel.state.value.userProfile)
    }

    // endregion

    // region start tracking

    @Test
    fun `starting tracking without a saved profile requests one`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertEquals(listOf<RouteEvent>(RouteEvent.RequestUserProfile), events)
    }

    @Test
    fun `starting tracking with a profile and a route navigates with the same payload`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        viewModel.onAction(RouteAction.ActivityTypeSelected(ActivityType.Walking))

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertEquals(
            listOf<RouteEvent>(
                RouteEvent.NavigateToTracking(
                    startPoint = START,
                    plannedRoutePoints = GENERATED_ROUTE.points.map { it.coordinates },
                    activityType = ActivityType.Walking
                )
            ),
            events
        )
    }

    @Test
    fun `starting tracking with a profile but no route emits nothing`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertTrue(events.isEmpty())
    }

    @Test
    fun `starting tracking with a generated route that has no points emits nothing`() = runTest(testScheduler) {
        userProfileRepository.userProfile = PROFILE
        directionsRepository.closedRouteResult = Result.success(Route(points = emptyList(), distanceMeters = 0.0))
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertTrue(events.isEmpty())
    }

    @Test
    fun `starting tracking with a route but no start point emits nothing`() = runTest(testScheduler) {
        // The only way to hold a route without a start point today: a reset whose location reload fails
        // while a generation is in flight, so the stale route lands afterwards (pinned by the
        // "reset while generating currently lets the stale result land" test).
        userProfileRepository.userProfile = PROFILE
        val gate = CompletableDeferred<Unit>()
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        directionsRepository.gate = gate
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())
        viewModel.onAction(RouteAction.ResetClicked)
        gate.complete(Unit)
        testScheduler.runCurrent()
        assertNull(viewModel.state.value.startPoint)
        assertEquals(GENERATED_ROUTE, viewModel.state.value.generatedRoute)
        val eventsBefore = events.size

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertEquals(emptyList(), events.drop(eventsBefore))
    }

    @Test
    fun `starting tracking after saving a profile navigates without requesting a profile`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        viewModel.onAction(RouteAction.UserProfileSaved(72.5))
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertEquals(
            listOf<RouteEvent>(
                RouteEvent.NavigateToTracking(
                    startPoint = START,
                    plannedRoutePoints = listOf(START, WP_A, WP_B, WP_C, START),
                    activityType = ActivityType.Running
                )
            ),
            events
        )
    }

    @Test
    fun `starting tracking reads the profile from the repository, not from the state`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        userProfileRepository.userProfile = PROFILE
        assertNull(viewModel.state.value.userProfile)

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertIs<RouteEvent.NavigateToTracking>(events.single())
    }

    // endregion

    // region events

    @Test
    fun `events sent before anyone collects are delivered in order once a collector subscribes`() =
        runTest(testScheduler) {
            locationRepository.currentLocationResult = Result.failure(RouteError.MissingLocationPermission())
            val viewModel = createViewModel()
            testScheduler.runCurrent()
            locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())
            viewModel.onAction(RouteAction.LocationPermissionGranted)
            testScheduler.runCurrent()
            viewModel.onAction(RouteAction.StartTrackingClicked)
            testScheduler.runCurrent()

            val events = collectEvents(viewModel)
            testScheduler.runCurrent()

            assertEquals(
                listOf(
                    RouteEvent.ShowError(RouteUiError.MissingLocationPermission),
                    RouteEvent.RequestLocationPermission,
                    RouteEvent.ShowError(RouteUiError.LocationUnavailable),
                    RouteEvent.RequestUserProfile
                ),
                events
            )
        }

    // endregion

    // region reset

    @Test
    fun `reset restores defaults and reloads location and profile`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.tapWaypoints(WP_A, WP_B, WP_C)
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        viewModel.onAction(RouteAction.ActivityTypeSelected(ActivityType.Cycling))
        locationRepository.currentLocationResult = Result.success(OTHER_START)
        userProfileRepository.userProfile = PROFILE

        viewModel.onAction(RouteAction.ResetClicked)
        testScheduler.runCurrent()

        assertEquals(RouteState(startPoint = OTHER_START, userProfile = PROFILE), viewModel.state.value)
        assertEquals(2, locationRepository.getCurrentLocationCalls)
        assertEquals(2, userProfileRepository.getUserProfileCalls)
    }

    // endregion

    private companion object {
        val START = Coordinates(latitude = 52.52, longitude = 13.405)
        val OTHER_START = Coordinates(latitude = 48.137, longitude = 11.575)
        val WP_A = Coordinates(latitude = 52.521, longitude = 13.406)
        val WP_B = Coordinates(latitude = 52.522, longitude = 13.407)
        val WP_C = Coordinates(latitude = 52.523, longitude = 13.408)
        val WP_D = Coordinates(latitude = 52.524, longitude = 13.409)
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
        val OTHER_ROUTE = Route(
            points = listOf(RoutePoint(START, 0), RoutePoint(WP_C, 1), RoutePoint(START, 2)),
            distanceMeters = 567.0
        )
    }
}
