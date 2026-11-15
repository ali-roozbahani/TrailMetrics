package dev.roozbahani.trailmetrics

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/** [OpenTrackingRequestEffect]: a request to open the live session is forwarded once and reset. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class OpenTrackingRequestEffectTest {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val requested = mutableStateOf(false)
    private var opened = 0

    private fun setContent() {
        rule.setContent { OpenTrackingRequestEffect(requested) { opened++ } }
        rule.waitForIdle()
    }

    @Test
    fun `nothing is opened without a request`() {
        setContent()

        assertEquals(0, opened)
    }

    @Test
    fun `a request is forwarded once and reset`() {
        setContent()

        requested.value = true
        rule.waitForIdle()

        assertEquals(1, opened)
        assertFalse(requested.value)
    }

    @Test
    fun `a request present at the first composition is forwarded`() {
        requested.value = true

        setContent()

        assertEquals(1, opened)
        assertFalse(requested.value)
    }

    @Test
    fun `a second request is forwarded again`() {
        setContent()
        requested.value = true
        rule.waitForIdle()

        requested.value = true
        rule.waitForIdle()

        assertEquals(2, opened)
    }
}
