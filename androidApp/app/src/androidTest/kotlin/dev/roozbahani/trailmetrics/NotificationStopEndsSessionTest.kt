package dev.roozbahani.trailmetrics

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.regex.Pattern
import kotlin.test.assertNotNull

/**
 * The notification's own Stop ends the session: the real tap crosses the `PendingIntent` that carries
 * the `StopTrackingAuthorization` secret, the Activity launch and the discard in `MainActivity`.
 */
@RunWith(AndroidJUnit4::class)
class NotificationStopEndsSessionTest {

    @get:Rule
    val session = LiveSessionRule()

    @Test
    fun tappingTheNotificationStopEndsTheSession() {
        val device = session.device
        device.openNotification()
        // Matched case-insensitively: a notification action label can render in capitals.
        val stop = By.text(Pattern.compile("Stop", Pattern.CASE_INSENSITIVE))
        assertNotNull(device.wait(Until.findObject(stop), LiveSessionRule.WAIT_MS), "the notification's Stop action never appeared")

        session.clickInShade(stop, "the notification's Stop action could not be tapped")

        session.eventually("the session is still ${session.manager.currentState.value::class.simpleName} after the notification's Stop") {
            session.manager.currentState.value == TrackingState.Idle
        }
    }
}
