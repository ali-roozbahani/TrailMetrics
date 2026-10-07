package dev.roozbahani.trailmetrics.feature.route

import android.Manifest
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.stringRes
import dev.roozbahani.trailmetrics.core.error.toUiError
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.feature.route.di.routeModule
import dev.roozbahani.trailmetrics.feature.route.fakes.FakeDirectionsRepository
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * [RouteRoot] with the real [RouteViewModel] from [routeModule], on fake repositories, under
 * Robolectric. Navigation lives in `androidApp/app`, so "started tracking" is a call of the
 * `onStartTrackingClicked` callback. The directions call is held with the fake's `gate` to see
 * what the screen shows while it is in flight and after it returns.
 */
@RunWith(RobolectricTestRunner::class)
// A phone-sized screen, so the profile sheet opens fully and its Save button is on screen.
@Config(sdk = [35], qualifiers = "w411dp-h891dp")
class RouteScreenTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val testScheduler = TestCoroutineScheduler()
    private val locationRepository = FakeLocationRepository(Result.success(START))
    private val directionsRepository = FakeDirectionsRepository(Result.success(GENERATED_ROUTE))
    private val userProfileRepository = FakeUserProfileRepository()
    private val robot = RouteScreenRobot(composeRule)
    private val startTrackingCalls = mutableListOf<StartTrackingCall>()

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        startKoin {
            modules(
                routeModule,
                module {
                    single<UserProfileRepository> { userProfileRepository }
                    factory { GetCurrentLocationUseCase(locationRepository) }
                    factory { GenerateClosedRouteUseCase(directionsRepository) }
                }
            )
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    @After
    fun tearDown() {
        stopKoin()
        Dispatchers.resetMain()
    }

    private fun showRoute() = robot.setContent(
        onStartTrackingClicked = { start, points, type -> startTrackingCalls += StartTrackingCall(start, points, type) }
    )

    /** Shows the screen with [waypoints] placed and, with a [gate], Generate tapped and its call held. */
    private fun showRouteGenerating(vararg waypoints: Coordinates, gate: CompletableDeferred<Unit>?) =
        showRoute().longPressMap(*waypoints).also { directionsRepository.gate = gate }.clickGenerate()

    // region stale results

    @Test
    fun `Reset while Generate is in flight leaves no route on screen once the call returns`() {
        val gate = CompletableDeferred<Unit>()
        showRouteGenerating(WP_A, WP_B, WP_C, gate = gate)
            .assertGenerateLoading()
            .clickResetIcon()

        gate.complete(Unit)

        robot.waitForIdle()
            .assertPanelNotShown()
            .assertNotLoading()
            .assertGenerateDisabled()
        assertEquals(1, directionsRepository.requests.size)
    }

    @Test
    fun `a waypoint added while Generate is in flight leaves no route on screen once the call returns`() {
        val gate = CompletableDeferred<Unit>()
        showRouteGenerating(WP_A, WP_B, WP_C, gate = gate)
            .assertGenerateLoading()
            .longPressMap(WP_D)

        gate.complete(Unit)

        robot.waitForIdle()
            .assertPanelNotShown()
            .assertNotLoading()
            .assertGenerateEnabled()
        assertEquals(1, directionsRepository.requests.size)
    }

    @Test
    fun `a waypoint removed while Generate is in flight leaves no route on screen once the call returns`() {
        val gate = CompletableDeferred<Unit>()
        showRouteGenerating(WP_A, WP_B, WP_C, WP_D, gate = gate)
            .assertGenerateLoading()
            .tapWaypointMarker(RoutePoint(WP_B, order = 1))

        gate.complete(Unit)

        robot.waitForIdle()
            .assertPanelNotShown()
            .assertNotLoading()
            .assertGenerateEnabled()
        assertEquals(1, directionsRepository.requests.size)
    }

    // endregion

    // region a shown route

    @Test
    fun `a map long-press after a route is shown hides the route until a new one is generated`() {
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .assertPanelShown()
            .assertGenerateNotShown()
            .longPressMap(WP_D)
            .assertPanelNotShown()
            .assertGenerateEnabled()
            .clickGenerate()
            .assertPanelShown()
            .assertGenerateNotShown()

        assertEquals(2, directionsRepository.requests.size)
    }

    @Test
    fun `removing a waypoint after a route is shown hides the route`() {
        showRouteGenerating(WP_A, WP_B, WP_C, WP_D, gate = null)
            .assertPanelShown()
            .tapWaypointMarker(RoutePoint(WP_D, order = 3))
            .assertPanelNotShown()
            .assertGenerateEnabled()
    }

    @Test
    fun `the panel's Reset hides the route and the waypoints`() {
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .assertPanelShown()
            .clickResetInPanel()
            .assertPanelNotShown()
            .assertGenerateDisabled()
    }

    // endregion

    // region Generate

    @Test
    fun `Generate is enabled only from the third waypoint on`() {
        showRoute()
            .assertGenerateDisabled()
            .longPressMap(WP_A, WP_B)
            .assertGenerateDisabled()
            .longPressMap(WP_C)
            .assertGenerateEnabled()
    }

    @Test
    fun `Generate stays disabled with three waypoints while there is no start point`() {
        locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())

        showRoute()
            .longPressMap(WP_A, WP_B, WP_C)
            .assertGenerateDisabled()

        assertEquals(0, directionsRepository.requests.size)
    }

    @Test
    fun `while the directions call is in flight Generate is disabled and shows the loading indicator`() {
        val gate = CompletableDeferred<Unit>()
        showRouteGenerating(WP_A, WP_B, WP_C, gate = gate)
            .assertGenerateLoading()
            .assertPanelNotShown()

        gate.complete(Unit)

        robot.waitForIdle()
            .assertNotLoading()
            .assertPanelShown()
    }

    @Test
    fun `tapping Generate twice while the call is in flight sends one directions request`() {
        val gate = CompletableDeferred<Unit>()
        directionsRepository.gate = gate
        showRoute()
            .longPressMap(WP_A, WP_B, WP_C)
            .doubleTapGenerate()
            .waitForIdle()

        assertEquals(1, directionsRepository.requests.size)

        gate.complete(Unit)
        robot.waitForIdle().assertPanelShown()
        assertEquals(1, directionsRepository.requests.size)
    }

    @Test
    fun `a failed directions call shows the error and Generate can be tapped again`() {
        val error = RouteError.DirectionsApiError(IllegalStateException("quota exceeded"))
        directionsRepository.closedRouteResult = Result.failure(error)

        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .assertMessageShown(error.toUiError().stringRes)
            .assertPanelNotShown()
            .assertNotLoading()
            .assertGenerateEnabled()

        directionsRepository.closedRouteResult = Result.success(GENERATED_ROUTE)
        robot.waitForSnackbarToHide()
            .clickGenerate()
            .assertPanelShown()
        assertEquals(2, directionsRepository.requests.size)
    }

    // endregion

    // region Start Tracking and the profile sheet

    @Test
    fun `Start Tracking with a saved profile starts tracking once with the route and the activity type`() {
        userProfileRepository.userProfile = PROFILE

        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .assertActivityTypeSelected(ActivityType.Running)
            .clickStartTracking()
            .waitForIdle()
            .assertProfileSheetNotShown()

        assertEquals(listOf(StartTrackingCall(START, ROUTE_COORDINATES, ActivityType.Running)), startTrackingCalls)
    }

    @Test
    fun `tapping Start Tracking twice while the profile read is in flight starts tracking once`() {
        userProfileRepository.userProfile = PROFILE
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null).assertPanelShown()
        val profileGate = CompletableDeferred<Unit>()
        userProfileRepository.getUserProfileGate = profileGate

        robot.doubleTapStartTracking().waitForIdle()
        assertEquals(emptyList(), startTrackingCalls)

        profileGate.complete(Unit)
        robot.waitForIdle()

        assertEquals(1, startTrackingCalls.size)
        assertEquals(listOf(StartTrackingCall(START, ROUTE_COORDINATES, ActivityType.Running)), startTrackingCalls)
    }

    @Test
    fun `Start Tracking passes the activity type selected in the panel`() {
        userProfileRepository.userProfile = PROFILE

        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .selectActivityType(ActivityType.Cycling)
            .assertActivityTypeSelected(ActivityType.Cycling)
            .clickStartTracking()
            .waitForIdle()

        assertEquals(listOf(StartTrackingCall(START, ROUTE_COORDINATES, ActivityType.Cycling)), startTrackingCalls)
    }

    @Test
    fun `Start Tracking without a saved profile opens the profile sheet and does not start tracking`() {
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .clickStartTracking()
            .assertProfileSheetShown()

        assertEquals(emptyList(), startTrackingCalls)
    }

    @Test
    fun `the profile sheet's Save is disabled for an empty, non-numeric, zero or negative weight`() {
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .clickStartTracking()
            .assertProfileSheetShown()
            .assertSaveDisabled()
            .enterWeight("abc")
            .assertSaveDisabled()
            .enterWeight("0")
            .assertSaveDisabled()
            .enterWeight("-3")
            .assertSaveDisabled()

        assertEquals(emptyList(), userProfileRepository.savedProfiles)
    }

    @Test
    fun `the profile sheet saves a valid weight once and closes`() {
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null)
            .clickStartTracking()
            .enterWeight("70.5")
            .assertSaveEnabled()
            .clickSave()
            .assertProfileSheetNotShown()

        assertEquals(listOf(UserProfile(weightKg = 70.5)), userProfileRepository.savedProfiles)
        assertEquals(emptyList(), startTrackingCalls)
    }

    // endregion

    // region events while an error is shown

    @Test
    fun `Start Tracking retried while the error of a failed profile read is shown starts tracking at once`() {
        userProfileRepository.userProfile = PROFILE
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null).assertPanelShown()
        userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")
        robot.clickStartTracking()
            .waitForIdle()
            .assertMessageShown(RouteUiError.General.stringRes)
        assertEquals(emptyList(), startTrackingCalls)

        userProfileRepository.getUserProfileFailure = null
        robot.startTrackingThroughViewModel().waitForIdle()

        // The test clock has not passed the snackbar's duration: the error is still shown.
        robot.assertMessageShown(RouteUiError.General.stringRes)
        assertEquals(listOf(StartTrackingCall(START, ROUTE_COORDINATES, ActivityType.Running)), startTrackingCalls)
    }

    @Test
    fun `Start Tracking retried without a profile while the error is shown opens the profile sheet at once`() {
        showRouteGenerating(WP_A, WP_B, WP_C, gate = null).assertPanelShown()
        userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")
        robot.clickStartTracking()
            .waitForIdle()
            .assertMessageShown(RouteUiError.General.stringRes)
            .assertProfileSheetNotShown()

        userProfileRepository.getUserProfileFailure = null
        robot.startTrackingThroughViewModel().waitForIdle()

        robot.assertMessageShown(RouteUiError.General.stringRes)
            .assertProfileSheetShown()
        assertEquals(emptyList(), startTrackingCalls)
    }

    @Test
    fun `a missing location permission shows its error and asks for the permission at once`() {
        locationRepository.currentLocationResult = Result.failure(RouteError.MissingLocationPermission())

        showRoute().waitForIdle()

        robot.assertMessageShown(RouteError.MissingLocationPermission().toUiError().stringRes)
        val request = assertNotNull(shadowOf(composeRule.activity).lastRequestedPermission, "a permission request")
        assertContentEquals(LOCATION_PERMISSIONS, request.requestedPermissions)
    }

    @Test
    fun `two errors in a row are shown one after the other in order`() {
        locationRepository.currentLocationResult = Result.failure(RouteError.LocationUnavailable())
        userProfileRepository.getUserProfileFailure = IllegalStateException("database locked")
        val locationError = RouteError.LocationUnavailable().toUiError().stringRes

        // The ViewModel's init reads the location first, then the profile.
        showRoute()
            .waitForIdle()
            .assertMessageShown(locationError)
            .assertMessageNotShown(RouteUiError.General.stringRes)
            .waitForSnackbarToHide()
            .assertMessageNotShown(locationError)
            .assertMessageShown(RouteUiError.General.stringRes)
            .waitForSnackbarToHide()
            .assertMessageNotShown(RouteUiError.General.stringRes)
    }

    // endregion

    private data class StartTrackingCall(
        val startPoint: Coordinates,
        val plannedRoutePoints: List<Coordinates>,
        val activityType: ActivityType
    )

    private companion object {
        val START = Coordinates(latitude = 52.52, longitude = 13.405)
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
        val ROUTE_COORDINATES = GENERATED_ROUTE.points.map { it.coordinates }
        val LOCATION_PERMISSIONS = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
    }
}
