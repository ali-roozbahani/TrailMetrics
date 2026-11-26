package dev.roozbahani.trailmetrics.data.tracking

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals

/** The restart notices' text comes from the string resources of `data`, the same text as before it moved there. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RestartNoticeTextAndroidHostTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun `a paused notice shows the distance in meters and offers to continue`() {
        assertEquals("Paused - 850 m, tap to continue", restartNoticeText(context, RestartNotice.Paused(850.4)))
    }

    @Test
    fun `a paused notice over a kilometer shows kilometers`() {
        assertEquals("Paused - 1.23 km, tap to continue", restartNoticeText(context, RestartNotice.Paused(1234.0)))
    }

    @Test
    fun `a finished notice says it is not saved and offers to save`() {
        assertEquals("Finished - not saved, tap to save", restartNoticeText(context, RestartNotice.Finished))
    }

    @Test
    fun `a restore-failed notice says the session could not be restored and offers to open the app`() {
        assertEquals(
            "Could not restore your saved session, tap to open",
            restartNoticeText(context, RestartNotice.RestoreFailed)
        )
    }
}
