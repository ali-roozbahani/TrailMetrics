package dev.roozbahani.trailmetrics

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.material3.Text
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A canary: it asserts nothing about the app. `runTest` under a Compose rule fails a test when an earlier test in
 * the same JVM left an uncaught coroutine exception ("There were uncaught exceptions before the test started"), so
 * this class shows such a leak. Its name sorts after the other classes of the module (the order does not matter for
 * any test; for the canary it decides only whether it can see a leak made by a class that ran before it). If it
 * fails, the failure message names the exception that an earlier class left behind (its `Suppressed:` lines).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class UncaughtExceptionCanaryTest {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun `no earlier test left an uncaught coroutine exception`() {
        rule.setContent { Text(CANARY_TEXT) }

        rule.onNodeWithText(CANARY_TEXT).assertExists()
    }

    private companion object {
        const val CANARY_TEXT = "canary"
    }
}
