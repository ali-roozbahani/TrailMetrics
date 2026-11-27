package dev.roozbahani.trailmetrics.data.tracking

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertTrue

/**
 * The tracking service's notification texts (title, text, the Stop action label, the channel name) are string resources
 * of `data` (owner decision of 2026-11-25: no user-visible text in code). Looked up by name, so the test also compiles
 * against code that had them as Kotlin literals.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TrackingNotificationResourcesAndroidHostTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `the tracking notification texts are string resources`() {
        val missing = listOf(
            "tracking_notification_title",
            "tracking_notification_tracking",
            "tracking_notification_paused",
            "tracking_notification_setting_up",
            "tracking_notification_stop",
            "tracking_notification_channel"
        ).filter { name -> context.resources.getIdentifier(name, "string", context.packageName) == 0 }

        assertTrue(missing.isEmpty(), "not string resources of data: $missing")
    }
}
