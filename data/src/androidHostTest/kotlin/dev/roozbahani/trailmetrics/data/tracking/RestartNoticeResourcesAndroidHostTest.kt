package dev.roozbahani.trailmetrics.data.tracking

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertTrue

/**
 * The three restart notices are string resources of `data` (owner decision of 2026-11-25: no user-visible text in
 * code). Looked up by name, so the test also compiles against code that had the notices as Kotlin literals.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RestartNoticeResourcesAndroidHostTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `the three restart notices are string resources`() {
        val missing = listOf("restart_notice_paused", "restart_notice_finished", "restart_notice_restore_failed")
            .filter { name -> context.resources.getIdentifier(name, "string", context.packageName) == 0 }

        assertTrue(missing.isEmpty(), "not string resources of data: $missing")
    }
}
