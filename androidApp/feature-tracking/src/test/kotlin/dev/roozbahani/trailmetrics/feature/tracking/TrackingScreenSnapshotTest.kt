package dev.roozbahani.trailmetrics.feature.tracking

import android.Manifest
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreenFixture.Companion.END
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreenFixture.Companion.START
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreenFixture.Companion.WALKED_ROUTE
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeGoogleMap
import dev.roozbahani.trailmetrics.feature.tracking.fakes.ShadowMapView
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The Finish button's path with a map: `TrackingScreen` keeps the `GoogleMap` that maps-compose's
 * `MapEffect` hands it, and Finish asks it for `snapshot { }`, which on a device calls back later.
 * Here the map is rendered (no `LocalInspectionMode`) over [ShadowMapView], so `MapEffect` gets a
 * real `GoogleMap` built on [FakeGoogleMap]'s delegate; the test decides when each snapshot
 * callback arrives. Everything else is as in [TrackingScreenTest].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h891dp", shadows = [ShadowMapView::class])
class TrackingScreenSnapshotTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val fixture = TrackingScreenFixture()
    private val robot = TrackingScreenRobot(composeRule)
    private val fakeMap = FakeGoogleMap()
    private var navigateBackCalls = 0

    @Before
    fun setUp() {
        FakeGoogleMap.installFactories()
        FakeGoogleMap.current = fakeMap
        fixture.setUp()
    }

    @After
    fun tearDown() {
        fixture.tearDown()
        FakeGoogleMap.current = null
    }

    /** Starts a session on a rendered map and walks the planned route to its end. */
    private fun showReachedDestination(): TrackingScreenRobot {
        shadowOf(composeRule.activity.application).grantPermissions(
            Manifest.permission.POST_NOTIFICATIONS,
            Manifest.permission.ACCESS_FINE_LOCATION
        )
        robot.setContent(
            startPoint = START,
            plannedRoutePoints = WALKED_ROUTE,
            onNavigateBack = { navigateBackCalls++ },
            inspectionMode = false
        ).clickStart()
        fixture.receiveLocation(END, millisAfterStart = 60_000L)
        return robot.waitForIdle().assertCompletedCard()
    }

    private fun filesDir(): File = composeRule.activity.filesDir

    @Test
    fun `Finish waits for the map snapshot and saves the activity with the snapshot file`() {
        showReachedDestination().clickFinish().waitForIdle()

        assertEquals(1, fakeMap.snapshotRequests)
        assertEquals(0, fixture.activityHistoryRepository.savedActivities.size, "nothing saved before the snapshot")
        assertEquals(0, navigateBackCalls)

        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()

        val path = assertNotNull(fixture.activityHistoryRepository.savedActivities.single().snapshotFilePath)
        assertSnapshotFileUnderFilesDir(path)
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `a double tap on Finish with both snapshots delivered later saves one activity and signals Saved once`() {
        showReachedDestination().doubleTapFinish().waitForIdle()

        assertEquals(2, fakeMap.snapshotRequests, "each tap asks the map for a snapshot")
        assertEquals(0, fixture.activityHistoryRepository.savedActivities.size)

        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()
        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()

        assertEquals(1, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(1, navigateBackCalls)
        val record = fixture.activityHistoryRepository.savedActivities.single()
        assertSnapshotFileUnderFilesDir(assertNotNull(record.snapshotFilePath))
    }

    @Test
    fun `a double tap on Finish whose first save is slow saves one activity`() {
        val gate = CompletableDeferred<Unit>()
        fixture.activityHistoryRepository.saveActivityGate = gate
        showReachedDestination().doubleTapFinish().waitForIdle()

        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()
        assertEquals(0, fixture.activityHistoryRepository.savedActivities.size)

        gate.complete(Unit)
        robot.waitForIdle()
        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()

        assertEquals(1, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `a snapshot without a bitmap saves the activity without a snapshot file`() {
        showReachedDestination().clickFinish().waitForIdle()

        composeRule.runOnUiThread { fakeMap.deliverSnapshot(null) }
        robot.waitForIdle()

        assertNull(fixture.activityHistoryRepository.savedActivities.single().snapshotFilePath)
        assertEquals(1, navigateBackCalls)
    }

    private fun assertSnapshotFileUnderFilesDir(path: String) {
        val file = File(path)
        assertTrue(file.isFile, "$path exists")
        assertEquals(filesDir().canonicalFile, file.canonicalFile.parentFile)
        assertTrue(file.name.endsWith(".png"), "$path is a PNG file name")
        assertNotNull(BitmapFactory.decodeFile(path), "$path decodes")
    }

    private fun bitmap(width: Int, height: Int): Bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
}
