package dev.roozbahani.trailmetrics

import android.Manifest
import android.app.Application
import android.content.Intent
import android.content.pm.ApplicationInfo
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** The debug crash check: registered only in a debuggable build, behind `DUMP`, and it throws for `crash` only. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class CrashReportingCheckTest {

    private val application: Application = RuntimeEnvironment.getApplication()

    private fun registeredCheckReceivers() = shadowOf(application).registeredReceivers
        .filter { it.broadcastReceiver is CrashReportingCheckReceiver }

    private fun intent(kind: String?) = Intent(CrashReportingCheckReceiver.ACTION).apply {
        if (kind != null) putExtra(CrashReportingCheckReceiver.EXTRA_KIND, kind)
    }

    @Test
    fun `a debuggable build registers the receiver for the check action, only for senders holding DUMP`() {
        application.applicationInfo.flags = application.applicationInfo.flags or ApplicationInfo.FLAG_DEBUGGABLE

        installCrashReportingCheck(application)

        val receiver = registeredCheckReceivers().single()
        assertTrue(receiver.intentFilter.hasAction(CrashReportingCheckReceiver.ACTION))
        assertEquals(Manifest.permission.DUMP, receiver.broadcastPermission)
        assertEquals(Manifest.permission.DUMP, CrashReportingCheckReceiver.SENDER_PERMISSION)
    }

    @Test
    fun `a release build registers nothing`() {
        application.applicationInfo.flags =
            application.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE.inv()

        installCrashReportingCheck(application)

        assertTrue(registeredCheckReceivers().isEmpty())
    }

    @Test
    fun `the crash kind throws the deliberate exception`() {
        assertFailsWith<CrashReportingCheckException> {
            CrashReportingCheckReceiver().onReceive(application, intent("crash"))
        }
    }

    @Test
    fun `an unknown or missing kind does not throw`() {
        val receiver = CrashReportingCheckReceiver()

        receiver.onReceive(application, intent("anr"))
        receiver.onReceive(application, intent(null))
    }
}
