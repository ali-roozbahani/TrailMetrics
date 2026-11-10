package dev.roozbahani.trailmetrics.feature.route

import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeRouteDraftStore
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.route.StoredRouteDraft
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.feature.route.fakes.FakeDirectionsRepository
import dev.roozbahani.trailmetrics.feature.route.fakes.inMemoryRouteDraftKeeper
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
import kotlin.test.assertTrue

/** How [RouteViewModel] restores, saves and clears the stored route draft (process death). */
class RouteViewModelDraftTest {

    private val testScheduler = TestCoroutineScheduler()

    private val locationRepository = FakeLocationRepository(Result.success(CURRENT_LOCATION))
    private val directionsRepository = FakeDirectionsRepository(Result.success(GENERATED_ROUTE))
    private val userProfileRepository = FakeUserProfileRepository()
    private val store = FakeRouteDraftStore()
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

    private fun createViewModel() = RouteViewModel(
        getCurrentLocationUseCase = GetCurrentLocationUseCase(locationRepository),
        generateClosedRouteUseCase = GenerateClosedRouteUseCase(directionsRepository),
        userProfileRepository = userProfileRepository,
        routeDraftKeeper = inMemoryRouteDraftKeeper(testScheduler, store, logger)
    )

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.collectEvents(viewModel: RouteViewModel): List<RouteEvent> {
        val events = mutableListOf<RouteEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        return events
    }

    // region restore

    @Test
    fun `a stored plan is restored with its markers route and activity type`() = runTest(testScheduler) {
        store.stored = STORED_PLAN

        val viewModel = createViewModel()
        testScheduler.runCurrent()

        val state = viewModel.state.value
        assertEquals(STORED_START, state.startPoint, "the current location replaced the plan's start point")
        assertEquals(STORED_PLAN.waypoints, state.waypoints)
        assertEquals(GENERATED_ROUTE, state.generatedRoute)
        assertEquals(ActivityType.Cycling, state.selectedActivityType)
        assertEquals(1, store.loadCallCount)
    }

    @Test
    fun `restoring a plan writes nothing`() = runTest(testScheduler) {
        store.stored = STORED_PLAN

        createViewModel()
        testScheduler.runCurrent()

        assertEquals(emptyList(), store.savedDrafts)
        assertEquals(0, store.clearCallCount)
    }

    @Test
    fun `a stored plan of only a start point takes the current location`() = runTest(testScheduler) {
        store.stored = StoredRouteDraft(STORED_START, emptyList(), null, ActivityType.Walking)

        val viewModel = createViewModel()
        testScheduler.runCurrent()

        assertEquals(CURRENT_LOCATION, viewModel.state.value.startPoint)
        assertEquals(ActivityType.Walking, viewModel.state.value.selectedActivityType)
    }

    @Test
    fun `a location that arrives while the plan loads neither saves nor stops the restore`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        val gate = CompletableDeferred<Unit>()
        store.loadGate = gate

        val viewModel = createViewModel()
        testScheduler.runCurrent()
        assertEquals(CURRENT_LOCATION, viewModel.state.value.startPoint)
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(STORED_START, viewModel.state.value.startPoint)
        assertEquals(STORED_PLAN.waypoints, viewModel.state.value.waypoints)
        assertEquals(emptyList(), store.savedDrafts)
    }

    @Test
    fun `a stored start point alone does not replace a location that arrived first`() = runTest(testScheduler) {
        store.stored = StoredRouteDraft(STORED_START, emptyList(), null, ActivityType.Walking)
        val gate = CompletableDeferred<Unit>()
        store.loadGate = gate
        val viewModel = createViewModel()
        testScheduler.runCurrent()

        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(CURRENT_LOCATION, viewModel.state.value.startPoint)
        assertEquals(ActivityType.Walking, viewModel.state.value.selectedActivityType)
    }

    @Test
    fun `a waypoint tapped before the plan loads wins and the loaded plan is dropped`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        val gate = CompletableDeferred<Unit>()
        store.loadGate = gate
        val viewModel = createViewModel()
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.MapTapped(WP_A))
        gate.complete(Unit)
        testScheduler.runCurrent()

        val expected = RouteState(startPoint = CURRENT_LOCATION, waypoints = listOf(RoutePoint(WP_A, 0)))
        assertEquals(expected, viewModel.state.value)
        assertEquals(StoredRouteDraft(CURRENT_LOCATION, expected.waypoints, null, ActivityType.Running), store.stored)
    }

    @Test
    fun `an activity type chosen before the plan loads wins and the loaded plan is dropped`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        val gate = CompletableDeferred<Unit>()
        store.loadGate = gate
        val viewModel = createViewModel()
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.ActivityTypeSelected(ActivityType.Walking))
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(
            RouteState(startPoint = CURRENT_LOCATION, selectedActivityType = ActivityType.Walking),
            viewModel.state.value
        )
    }

    @Test
    fun `a failing read starts an empty plan without an error and keeps the stored row`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        store.loadFailure = IllegalStateException("corrupt row")
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()

        assertEquals(RouteState(startPoint = CURRENT_LOCATION), viewModel.state.value)
        assertEquals(emptyList(), events)
        assertTrue(logger.messages.single().contains("corrupt row"))
        assertEquals(STORED_PLAN, store.stored, "the stored row was replaced before the user changed the plan")
        assertEquals(0, store.clearCallCount)
    }

    @Test
    fun `after a failing read the first change of the plan replaces the stored row`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        store.loadFailure = IllegalStateException("corrupt row")
        val viewModel = createViewModel()
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.MapTapped(WP_A))
        testScheduler.runCurrent()

        assertEquals(
            StoredRouteDraft(CURRENT_LOCATION, listOf(RoutePoint(WP_A, 0)), null, ActivityType.Running),
            store.stored
        )
    }

    // endregion

    // region save

    @Test
    fun `nothing is written before the user changes the plan`() = runTest(testScheduler) {
        createViewModel()
        testScheduler.runCurrent()

        assertEquals(emptyList(), store.savedDrafts)
    }

    @Test
    fun `every change of waypoints route and activity type is saved`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        val a = RoutePoint(WP_A, 0)
        val b = RoutePoint(WP_B, 1)
        val c = RoutePoint(WP_C, 2)

        viewModel.onAction(RouteAction.MapTapped(WP_A))
        viewModel.onAction(RouteAction.MapTapped(WP_B))
        viewModel.onAction(RouteAction.MapTapped(WP_C))
        viewModel.onAction(RouteAction.ActivityTypeSelected(ActivityType.Cycling))
        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()
        viewModel.onAction(RouteAction.WaypointRemoved(b))
        testScheduler.runCurrent()

        val running = ActivityType.Running
        val cycling = ActivityType.Cycling
        assertEquals(
            listOf(
                StoredRouteDraft(CURRENT_LOCATION, listOf(a), null, running),
                StoredRouteDraft(CURRENT_LOCATION, listOf(a, b), null, running),
                StoredRouteDraft(CURRENT_LOCATION, listOf(a, b, c), null, running),
                StoredRouteDraft(CURRENT_LOCATION, listOf(a, b, c), null, cycling),
                StoredRouteDraft(CURRENT_LOCATION, listOf(a, b, c), GENERATED_ROUTE, cycling),
                StoredRouteDraft(CURRENT_LOCATION, listOf(a, c.copy(order = 1)), null, cycling),
            ),
            store.savedDrafts
        )
    }

    @Test
    fun `a new start point from the current location is saved once the plan is kept`() = runTest(testScheduler) {
        locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())
        val viewModel = createViewModel()
        testScheduler.runCurrent()
        viewModel.onAction(RouteAction.MapTapped(WP_A))
        testScheduler.runCurrent()

        locationRepository.currentLocationResult = Result.success(CURRENT_LOCATION)
        viewModel.onAction(RouteAction.LocationPermissionGranted)
        testScheduler.runCurrent()

        assertEquals(
            StoredRouteDraft(CURRENT_LOCATION, listOf(RoutePoint(WP_A, 0)), null, ActivityType.Running),
            store.savedDrafts.last()
        )
    }

    @Test
    fun `a failing save is logged and planning goes on`() = runTest(testScheduler) {
        store.saveFailure = IllegalStateException("disk full")
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.MapTapped(WP_A))
        viewModel.onAction(RouteAction.MapTapped(WP_B))
        testScheduler.runCurrent()

        assertEquals(listOf(RoutePoint(WP_A, 0), RoutePoint(WP_B, 1)), viewModel.state.value.waypoints)
        assertEquals(emptyList(), events)
        assertEquals(2, logger.messages.count { it.contains("disk full") })
    }

    // endregion

    // region clear

    @Test
    fun `Reset clears the stored plan and keeps only the new start point`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        val viewModel = createViewModel()
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.ResetClicked)
        testScheduler.runCurrent()

        assertTrue(store.savedDrafts.first().isEmpty, "Reset did not clear the stored plan first")
        assertEquals(StoredRouteDraft(CURRENT_LOCATION, emptyList(), null, ActivityType.Running), store.stored)
    }

    @Test
    fun `Start Tracking clears the stored plan and keeps the plan on screen`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        userProfileRepository.userProfile = PROFILE
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()
        val before = viewModel.state.value

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertIs<RouteEvent.NavigateToTracking>(events.last())
        assertNull(store.stored)
        assertEquals(1, store.clearCallCount)
        assertEquals(before, viewModel.state.value)
    }

    @Test
    fun `Start Tracking that asks for the profile keeps the stored plan`() = runTest(testScheduler) {
        store.stored = STORED_PLAN
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        testScheduler.runCurrent()

        viewModel.onAction(RouteAction.StartTrackingClicked)
        testScheduler.runCurrent()

        assertEquals(listOf<RouteEvent>(RouteEvent.RequestUserProfile), events)
        assertEquals(STORED_PLAN, store.stored)
        assertEquals(0, store.clearCallCount)
    }

    // endregion

    private companion object {
        val CURRENT_LOCATION = Coordinates(latitude = 52.52, longitude = 13.405)
        val STORED_START = Coordinates(latitude = 48.137, longitude = 11.575)
        val WP_A = Coordinates(latitude = 52.521, longitude = 13.406)
        val WP_B = Coordinates(latitude = 52.522, longitude = 13.407)
        val WP_C = Coordinates(latitude = 52.523, longitude = 13.408)
        val PROFILE = UserProfile(weightKg = 70.0)
        val GENERATED_ROUTE = Route(
            points = listOf(RoutePoint(STORED_START, 0), RoutePoint(WP_A, 1), RoutePoint(STORED_START, 2)),
            distanceMeters = 1234.0
        )
        val STORED_PLAN = StoredRouteDraft(
            startPoint = STORED_START,
            waypoints = listOf(RoutePoint(WP_A, 0), RoutePoint(WP_B, 1), RoutePoint(WP_C, 2)),
            generatedRoute = GENERATED_ROUTE,
            activityType = ActivityType.Cycling
        )
    }
}
