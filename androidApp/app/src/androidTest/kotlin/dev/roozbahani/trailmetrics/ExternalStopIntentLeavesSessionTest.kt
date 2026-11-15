package dev.roozbahani.trailmetrics

import android.app.NotificationManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import dev.roozbahani.trailmetrics.data.tracking.TrackingService
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * S1 (`tm-robustness`): `MainActivity` is exported, so a Stop intent from any other caller (here the
 * shell's `am start`, which has no `StopTrackingAuthorization` secret) must leave the live session alone.
 */
@RunWith(AndroidJUnit4::class)
class ExternalStopIntentLeavesSessionTest {

    @get:Rule
    val session = LiveSessionRule()

    @Test
    fun anExternalStopIntentLeavesTheLiveSessionAlone() {
        val device = session.device
        val packageName = session.packageName

        val result = device.executeShellCommand(
            "am start -n $packageName/.MainActivity -a ${TrackingService.ACTION_STOP_TRACKING}"
        )
        assertTrue(!result.contains("Error"), "am start failed: $result")

        // A positive signal first: the Activity is on screen, so the intent has been handled.
        assertNotNull(device.wait(Until.findObject(By.pkg(packageName)), LiveSessionRule.WAIT_MS), "MainActivity never came up")
        device.waitForIdle()

        assertIs<TrackingState.Tracking>(session.manager.currentState.value)
        val notifications = InstrumentationRegistry.getInstrumentation().targetContext
            .getSystemService(NotificationManager::class.java)
        assertEquals(1, notifications.activeNotifications.size, "the foreground notification is gone")
    }
}
