package dev.roozbahani.trailmetrics.data.tracking

import android.content.Intent
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class) // Intent extras need the Android framework
@Config(sdk = [35])
class StopTrackingAuthorizationTest {

    private fun stopIntent() = Intent(TrackingService.ACTION_STOP_TRACKING)

    @Test
    fun `an intent made by authorize is authorized`() {
        assertTrue(StopTrackingAuthorization.isAuthorized(StopTrackingAuthorization.authorize(stopIntent())))
    }

    @Test
    fun `an intent with the action only is not authorized`() {
        assertFalse(StopTrackingAuthorization.isAuthorized(stopIntent()))
    }

    @Test
    fun `no intent is not authorized`() {
        assertFalse(StopTrackingAuthorization.isAuthorized(null))
    }

    @Test
    fun `an intent with another secret is not authorized`() {
        val authorized = StopTrackingAuthorization.authorize(stopIntent())
        val extraName = checkNotNull(authorized.extras).keySet().single()
        val forged = stopIntent().putExtra(extraName, authorized.getStringExtra(extraName) + "0")

        assertFalse(StopTrackingAuthorization.isAuthorized(forged))
    }

    @Test
    fun `the secret is the same within a process and not trivial`() {
        val first = StopTrackingAuthorization.authorize(stopIntent())
        val second = StopTrackingAuthorization.authorize(stopIntent())
        val name = checkNotNull(first.extras).keySet().single()

        assertEquals(first.getStringExtra(name), second.getStringExtra(name))
        assertEquals(32, first.getStringExtra(name)?.length)
        assertNotEquals("0".repeat(32), first.getStringExtra(name))
    }
}
