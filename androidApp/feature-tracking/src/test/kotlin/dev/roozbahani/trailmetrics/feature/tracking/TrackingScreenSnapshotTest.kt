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

        assertEquals(1, fakeMap.snapshotRequests, "no second snapshot while the first is pending")
        assertEquals(0, fixture.activityHistoryRepository.savedActivities.size)

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
        showReachedDestination().clickFinish().waitForIdle()

        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()
        assertEquals(0, fixture.activityHistoryRepository.savedActivities.size)

        // The snapshot's callback released the screen's guard: a second tap during the slow save
        // reaches the ViewModel, whose own guard keeps it from saving the session twice.
        robot.clickFinish().waitForIdle()
        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()
        gate.complete(Unit)
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

    @Test
    fun `a double tap on Finish asks the map for one snapshot`() {
        showReachedDestination().doubleTapFinish().waitForIdle()

        assertEquals(1, fakeMap.snapshotRequests, "no second snapshot while the first is pending")
    }

    @Test
    fun `a double tap on Finish writes one snapshot file and saves one activity once its snapshot arrives`() {
        showReachedDestination().doubleTapFinish().waitForIdle()

        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()

        val file = snapshotFiles().single()
        val record = fixture.activityHistoryRepository.savedActivities.single()
        assertEquals(file.canonicalFile, File(assertNotNull(record.snapshotFilePath)).canonicalFile)
        assertEquals(1, navigateBackCalls, "Saved once")
    }

    @Test
    fun `a double tap on Finish leaves one snapshot file after every requested snapshot has arrived`() {
        showReachedDestination().doubleTapFinish().waitForIdle()

        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()
        // The file name has millisecond resolution: move the first file aside so that a second write
        // in the same millisecond is counted instead of overwriting it. The count does not change.
        val first = snapshotFiles().single()
        assertTrue(first.renameTo(File(first.parentFile, "first_${first.name}")))
        while (fakeMap.pendingSnapshotCount > 0) {
            composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
            robot.waitForIdle()
        }

        assertEquals(1, snapshotFiles().size, "files in filesDir: ${snapshotFiles().map { it.name }}")
        assertEquals(1, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `a Finish after a failed save asks for a new snapshot and saves the activity`() {
        fixture.activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
        showReachedDestination().clickFinish().waitForIdle()
        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()
        assertEquals(0, fixture.activityHistoryRepository.savedActivities.size)
        assertEquals(0, navigateBackCalls)

        fixture.activityHistoryRepository.saveActivityFailure = null
        robot.clickFinish().waitForIdle()

        assertEquals(2, fakeMap.snapshotRequests, "the first snapshot's callback released the guard")
        composeRule.runOnUiThread { fakeMap.deliverSnapshot(bitmap(width = 300, height = 200)) }
        robot.waitForIdle()
        val record = fixture.activityHistoryRepository.savedActivities.single()
        assertSnapshotFileUnderFilesDir(assertNotNull(record.snapshotFilePath))
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `a snapshot without a bitmap finishes once and does not block a later tap`() {
        showReachedDestination().clickFinish().waitForIdle()
        composeRule.runOnUiThread { fakeMap.deliverSnapshot(null) }
        robot.waitForIdle()

        assertNull(fixture.activityHistoryRepository.savedActivities.single().snapshotFilePath)
        assertEquals(1, navigateBackCalls)
        assertEquals(emptyList(), snapshotFiles())

        robot.clickFinish().waitForIdle()
        assertEquals(2, fakeMap.snapshotRequests, "the callback without a bitmap released the guard")
        composeRule.runOnUiThread { fakeMap.deliverSnapshot(null) }
        robot.waitForIdle()
        assertEquals(1, fixture.activityHistoryRepository.savedActivities.size, "the session is saved once")
        assertEquals(1, navigateBackCalls)
    }

    private fun snapshotFiles(): List<File> = filesDir().listFiles { file -> file.isFile }.orEmpty().toList()

    private fun assertSnapshotFileUnderFilesDir(path: String) {
        val file = File(path)
        assertTrue(file.isFile, "$path exists")
        assertEquals(filesDir().canonicalFile, file.canonicalFile.parentFile)
        assertTrue(file.name.endsWith(".png"), "$path is a PNG file name")
        assertNotNull(BitmapFactory.decodeFile(path), "$path decodes")
    }

    private fun bitmap(width: Int, height: Int): Bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
}
