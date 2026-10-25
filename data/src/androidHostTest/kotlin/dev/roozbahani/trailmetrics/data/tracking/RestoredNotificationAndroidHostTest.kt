package dev.roozbahani.trailmetrics.data.tracking

import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RestoredNotificationAndroidHostTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val packageManager = shadowOf(context.packageManager)

    private fun registerLauncherActivity() {
        val launcherActivity = ComponentName(context.packageName, "${context.packageName}.MainActivity")
        packageManager.addOrUpdateActivity(
            ActivityInfo().apply {
                packageName = launcherActivity.packageName
                name = launcherActivity.className
            }
        )
        packageManager.addIntentFilterForActivity(
            launcherActivity,
            IntentFilter(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
        )
    }

    @Test
    fun `the notice is a normal auto-cancel notification with the text and a tap target`() {
        registerLauncherActivity()

        val notice = buildRestoredNotification(context, "channel", android.R.drawable.ic_dialog_info, "Paused - 1 m")

        assertEquals("Paused - 1 m", notice.extras.getString(Notification.EXTRA_TEXT))
        assertTrue(notice.flags and Notification.FLAG_AUTO_CANCEL != 0)
        assertEquals(0, notice.flags and Notification.FLAG_ONGOING_EVENT)
        val tap = shadowOf(assertNotNull(notice.contentIntent)).savedIntent
        assertEquals(Intent.ACTION_MAIN, tap.action)
        assertEquals(context.packageName, tap.component?.packageName)
    }

    @Test
    fun `without a launcher Activity the notice cannot be built`() {
        assertFailsWith<IllegalStateException> {
            buildRestoredNotification(context, "channel", android.R.drawable.ic_dialog_info, "Finished - not saved")
        }
    }

    @Test
    fun `stopping the launcher cancels the restart notice and stops the service`() {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(TrackingService.RESTORED_NOTIFICATION_ID, Notification.Builder(context, "channel").build())
        assertNotNull(shadowOf(manager).getNotification(TrackingService.RESTORED_NOTIFICATION_ID))

        AndroidTrackingServiceLauncher(context).stop()

        assertNull(shadowOf(manager).getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
    }

    @Test
    fun `starting the launcher starts the service with an intent`() {
        AndroidTrackingServiceLauncher(context).start()

        val started = assertNotNull(shadowOf(context as android.app.Application).nextStartedService)
        assertEquals(TrackingService::class.java.name, started.component?.className)
    }
}
