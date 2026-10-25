package dev.roozbahani.trailmetrics

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import kotlinx.coroutines.flow.flowOf
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowToast
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** [SavedSessionOfferEvents]: what the user sees when the stored session could not be restored. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class SavedSessionOfferEventsTest {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun `RestoreFailed shows the message`() {
        rule.setContent { SavedSessionOfferEvents(flowOf(SavedSessionOfferEvent.RestoreFailed)) }
        rule.waitForIdle()

        assertEquals(rule.activity.getString(R.string.saved_session_restore_failed), ShadowToast.getTextOfLatestToast())
    }

    @Test
    fun `no event shows nothing`() {
        rule.setContent { SavedSessionOfferEvents(flowOf()) }
        rule.waitForIdle()

        assertNull(ShadowToast.getLatestToast())
    }
}
