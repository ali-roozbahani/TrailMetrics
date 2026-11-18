package dev.roozbahani.trailmetrics

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertNotNull

/**
 * #301: a live session is reachable from its notification when no Activity exists. Not provable on the
 * JVM: it needs the real shade, the system's handling of the `PendingIntent` and an Activity and task
 * that the system creates. (Names are camelCase: backtick names do not dex at minSdk 26.)
 */
@RunWith(AndroidJUnit4::class)
class NotificationBodyOpensTrackingTest {

    @get:Rule
    val session = LiveSessionRule()

    @Test
    fun tappingTheNotificationBodyOpensTheTrackingScreenOfTheLiveSession() {
        val device = session.device
        device.openNotification()
        val body = By.textContains("Tracking...")
        assertNotNull(
            device.wait(Until.findObject(body), LiveSessionRule.WAIT_MS),
            "the service's notification never appeared",
        )

        session.clickInShade(body, "the notification body could not be tapped")

        assertNotNull(
            device.wait(Until.findObject(By.pkg(session.packageName).text("Pause")), LiveSessionRule.WAIT_MS),
            "the Tracking screen (its Pause button) is not shown after tapping the notification body"
        )
    }
}
