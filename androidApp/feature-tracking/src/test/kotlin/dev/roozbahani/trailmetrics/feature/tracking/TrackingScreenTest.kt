package dev.roozbahani.trailmetrics.feature.tracking

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.error.stringRes
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreenFixture.Companion.END
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreenFixture.Companion.NEXT
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreenFixture.Companion.START
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreenFixture.Companion.WALKED_ROUTE
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeGoogleMap
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowActivity
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * [TrackingRoot] with the real [TrackingViewModel] from `trackingUiModule`, on fakes, under
 * Robolectric. The map is not rendered, so location fixes come from the fake location repository
 * and the Finish button has no map to snapshot (`TrackingScreenSnapshotTest` covers that path).
 * Navigation lives in `androidApp/app`, so "went back" is a call of the `onNavigateBack` callback;
 * `TrackingEvent.Saved` is seen the same way, as the Root's only reaction to it.
 */
@RunWith(RobolectricTestRunner::class)
// A phone-sized screen, as in the other feature modules' UI tests.
@Config(sdk = [35], qualifiers = "w411dp-h891dp")
class TrackingScreenTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val fixture = TrackingScreenFixture()
    private val robot = TrackingScreenRobot(composeRule)
    private var navigateBackCalls = 0

    @Before
    fun setUp() {
        FakeGoogleMap.installFactories()
        fixture.setUp()
    }

    @After
    fun tearDown() {
        fixture.tearDown()
    }

    /**
     * With [notificationsGranted], the notification permission the screen asks for on first
     * composition is already granted, so that request is answered at once and never pending: while
     * one request is pending, Android answers a second one (location) at once with nothing granted.
     */
    private fun showScreen(
        notificationsGranted: Boolean = true,
        viaNavHostEntry: Boolean = false
    ): TrackingScreenRobot {
        if (notificationsGranted) {
            shadowOf(composeRule.activity.application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        }
        return robot.setContent(
            startPoint = START,
            plannedRoutePoints = WALKED_ROUTE,
            onNavigateBack = { navigateBackCalls++ },
            viaNavHostEntry = viaNavHostEntry
        )
    }

    private fun grantLocationPermission() {
        shadowOf(composeRule.activity.application).grantPermissions(*LOCATION_PERMISSIONS)
    }

    /** Starts a session with the permission granted and keeps it at [START]. */
    private fun showStartedSession() = showScreen().also { grantLocationPermission() }.clickStart()

    /** Starts a session and walks the planned route to its end, which stops the session. */
    private fun showReachedDestination(): TrackingScreenRobot {
        showStartedSession()
        fixture.receiveLocation(END, millisAfterStart = 60_000L)
        return robot.waitForIdle()
    }

    private fun trackingState(): TrackingState = fixture.sessionManager.currentState.value

    /** Two fixes short of the route's end, so the speed (it needs two) and the calories have values. */
    private fun walkTwoFixes() {
        fixture.receiveLocation(NEXT, millisAfterStart = 30_000L)
        fixture.receiveLocation(NEAR_END, millisAfterStart = 60_000L)
    }

    private fun lastPermissionRequest(): ShadowActivity.PermissionsRequest? =
        shadowOf(composeRule.activity).lastRequestedPermission

    private fun TrackingScreenRobot.assertWalkedMetricsShown() = assertMetricsShown(
        distance = WALKED_DISTANCE,
        time = WALKED_TIME,
        speed = WALKED_SPEED,
        calories = WALKED_CALORIES
    )

    private fun lastRequestedPermissions(): Array<String> =
        assertNotNull(lastPermissionRequest(), "a permission request").requestedPermissions

    // region state rendering

    @Test
    fun `Idle shows only Start and no metrics`() {
        showScreen()
            .assertIdleControls()
            .assertMetricsNotShown()
            .assertCompletedCardNotShown()
    }

    @Test
    fun `Tracking right after Start shows Pause and Stop and placeholder metrics`() {
        showStartedSession()
            .assertTrackingControls()
            .assertMetricsShown(distance = "0 m", time = "00:00", speed = "-- km/h", calories = "-- kcal")
    }

    @Test
    fun `Tracking shows the metrics of the walked path as MetricsDisplay formats them`() {
        showStartedSession()
        walkTwoFixes()

        robot.waitForIdle()
            .assertTrackingControls()
            .assertWalkedMetricsShown()
    }

    @Test
    fun `Paused shows Resume and Stop and keeps the metrics`() {
        showStartedSession()
        walkTwoFixes()

        robot.clickPause()
            .assertPausedControls()
            .assertWalkedMetricsShown()
        assertIs<TrackingState.Paused>(trackingState())
    }

    @Test
    fun `reaching the end of the planned route shows the completed card with Finish`() {
        showReachedDestination()
            .assertCompletedCard()
            .assertMetricsNotShown()
        assertIs<TrackingState.Finished>(trackingState())
    }

    @Test
    fun `the NavHost entry point shows the same screen and passes navigation through`() {
        showScreen(viaNavHostEntry = true)
            .assertIdleControls()
            .clickBackButton()

        assertEquals(1, navigateBackCalls)
    }

    // endregion

    // region Start and the location permission

    @Test
    fun `on first composition the screen asks for the notification permission`() {
        showScreen(notificationsGranted = false).waitForIdle()

        assertContentEquals(arrayOf(Manifest.permission.POST_NOTIFICATIONS), lastRequestedPermissions())
    }

    @Test
    fun `Start with the location permission granted starts a session`() {
        showStartedSession()
            .assertTrackingControls()

        assertIs<TrackingState.Tracking>(trackingState())
        assertEquals(1, fixture.trackingServiceLauncher.startCalls)
        assertNull(lastPermissionRequest(), "no permission request")
    }

    @Test
    fun `Start with only the coarse location permission granted starts a session`() {
        showScreen()
        shadowOf(composeRule.activity.application).grantPermissions(Manifest.permission.ACCESS_COARSE_LOCATION)

        robot.clickStart().assertTrackingControls()

        assertIs<TrackingState.Tracking>(trackingState())
        assertNull(lastPermissionRequest(), "no permission request")
    }

    @Test
    fun `Start without the location permission asks for it and does not start`() {
        showScreen().clickStart()

        assertContentEquals(LOCATION_PERMISSIONS, lastRequestedPermissions())
        assertIs<TrackingState.Idle>(trackingState())
        robot.assertIdleControls()
        assertEquals(0, fixture.trackingServiceLauncher.startCalls)
    }

    @Test
    fun `granting the requested location permission starts a session at the start point`() {
        showScreen().clickStart()

        answerLocationPermissionRequest(granted = true)

        robot.waitForIdle().assertTrackingControls()
        val tracking = assertIs<TrackingState.Tracking>(trackingState())
        assertEquals(listOf(START), tracking.metrics.path)
    }

    @Test
    fun `denying the requested location permission does not start`() {
        showScreen().clickStart()

        answerLocationPermissionRequest(granted = false)

        robot.waitForIdle().assertIdleControls()
        assertIs<TrackingState.Idle>(trackingState())
    }

    @Test
    fun `a missing location permission during a session asks for the permission again`() {
        showStartedSession()
        shadowOf(composeRule.activity.application).denyPermissions(*LOCATION_PERMISSIONS)

        fixture.receiveUnavailable(RouteError.MissingLocationPermission())
        robot.waitForIdle()

        assertContentEquals(LOCATION_PERMISSIONS, lastRequestedPermissions())
    }

    // endregion

    // region Pause, Resume, Stop

    @Test
    fun `Pause then Resume returns to Tracking`() {
        showStartedSession()
            .clickPause()
            .assertPausedControls()
            .clickResume()
            .assertTrackingControls()

        assertIs<TrackingState.Tracking>(trackingState())
        assertEquals(0, navigateBackCalls)
    }

    @Test
    fun `Stop while tracking stops the session and navigates back once`() {
        showStartedSession().clickStop().waitForIdle()

        assertIs<TrackingState.Finished>(trackingState())
        assertEquals(1, fixture.trackingServiceLauncher.stopCalls)
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `Stop while paused stops the session and navigates back once`() {
        showStartedSession().clickPause().clickStop().waitForIdle()

        assertIs<TrackingState.Finished>(trackingState())
        assertEquals(1, navigateBackCalls)
    }

    // endregion

    // region Back and the exit dialog

    @Test
    fun `Back with no active session navigates back at once without a dialog`() {
        showScreen().clickBackButton().assertExitDialogNotShown()

        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `Back during a session shows the exit dialog and does not navigate`() {
        showStartedSession().clickBackButton().assertExitDialogShown()

        assertEquals(0, navigateBackCalls)
        assertIs<TrackingState.Tracking>(trackingState())
    }

    @Test
    fun `system Back during a paused session shows the exit dialog`() {
        showStartedSession().clickPause().pressSystemBack().assertExitDialogShown()

        assertEquals(0, navigateBackCalls)
    }

    @Test
    fun `dismissing the exit dialog keeps the session and does not navigate`() {
        showStartedSession()
            .clickBackButton()
            .dismissExit()
            .assertExitDialogNotShown()
            .assertTrackingControls()

        assertIs<TrackingState.Tracking>(trackingState())
        assertEquals(0, navigateBackCalls)
    }

    @Test
    fun `confirming the exit dialog stops the session and navigates back once`() {
        showStartedSession()
            .clickBackButton()
            .confirmExit()
            .waitForIdle()
            .assertExitDialogNotShown()

        assertIs<TrackingState.Finished>(trackingState())
        assertEquals(1, fixture.trackingServiceLauncher.stopCalls)
        assertEquals(1, navigateBackCalls)
    }

    // endregion

    // region errors

    @Test
    fun `a location error during a session shows its message`() {
        showStartedSession()

        fixture.receiveUnavailable(RouteError.LocationUnavailable())

        robot.waitForIdle().assertMessageShown(RouteUiError.LocationUnavailable.stringRes)
    }

    @Test
    fun `a profile that fails to load shows the general error`() {
        fixture.userProfileRepository.getUserProfileFailure = IllegalStateException("db closed")

        showScreen().waitForIdle().assertMessageShown(RouteUiError.General.stringRes)
    }

    // endregion

    // region Finish

    @Test
    fun `Finish saves the activity once and navigates back once`() {
        showReachedDestination().clickFinish().waitForIdle()

        val record = fixture.activityHistoryRepository.savedActivities.single()
        assertEquals(WALKED_ROUTE, record.plannedRoutePoints)
        assertEquals(listOf(START, END), record.actualPath)
        assertNull(record.snapshotFilePath)
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `a double tap on Finish saves one activity and signals Saved once`() {
        showReachedDestination().doubleTapFinish().waitForIdle()

        assertEquals(1, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `taps on Finish before and after a slow save completes save one activity`() {
        val gate = CompletableDeferred<Unit>()
        fixture.activityHistoryRepository.saveActivityGate = gate
        showReachedDestination().doubleTapFinish().waitForIdle()

        assertEquals(0, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(0, navigateBackCalls)

        gate.complete(Unit)
        robot.waitForIdle()
        assertEquals(1, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(1, navigateBackCalls)

        robot.clickFinish().waitForIdle()
        assertEquals(1, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(1, navigateBackCalls)
    }

    // endregion

    /** What the system's permission dialog returns for the location request the screen made. */
    private fun answerLocationPermissionRequest(granted: Boolean) {
        val request = assertNotNull(lastPermissionRequest(), "a permission request")
        assertContentEquals(LOCATION_PERMISSIONS, request.requestedPermissions)
        if (granted) grantLocationPermission()
        val result = if (granted) PackageManager.PERMISSION_GRANTED else PackageManager.PERMISSION_DENIED
        val grantResults = IntArray(request.requestedPermissions.size) { result }
        val data = Intent()
            .putExtra(RequestMultiplePermissions.EXTRA_PERMISSIONS, request.requestedPermissions)
            .putExtra(RequestMultiplePermissions.EXTRA_PERMISSION_GRANT_RESULTS, grantResults)
        composeRule.runOnUiThread {
            val registry = composeRule.activity.activityResultRegistry
            val delivered = registry.dispatchResult(request.requestCode, Activity.RESULT_OK, data)
            assertTrue(delivered, "a launcher waits for request ${request.requestCode}")
        }
    }

    private companion object {
        /** ~56 m before the route's end: farther than the completion threshold (25 m). */
        val NEAR_END = Coordinates(latitude = 52.0015, longitude = 13.000)

        // START -> NEXT -> NEAR_END is 0.0015 degrees of latitude (~166.8 m) in one minute.
        const val WALKED_DISTANCE = "166 m"
        const val WALKED_TIME = "01:00"

        // The speed over the last two fixes: ~55.6 m in 30 s, 6.67 km/h.
        const val WALKED_SPEED = "6.7 km/h"

        // Average 10.0 km/h: running MET 9.8 x 70 kg x 1/60 h = 11.4 kcal.
        const val WALKED_CALORIES = "11 kcal"

        val LOCATION_PERMISSIONS = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
    }
}
