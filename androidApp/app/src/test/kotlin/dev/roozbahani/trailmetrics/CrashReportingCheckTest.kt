package dev.roozbahani.trailmetrics

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

/** The debug crash and ANR check: registered only in a debuggable build, and each kind does its one thing. */
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
    fun `a debuggable build registers the receiver for the check action`() {
        application.applicationInfo.flags = application.applicationInfo.flags or ApplicationInfo.FLAG_DEBUGGABLE

        installCrashReportingCheck(application)

        val receivers = registeredCheckReceivers()
        assertEquals(1, receivers.size)
        assertTrue(receivers.single().intentFilter.hasAction(CrashReportingCheckReceiver.ACTION))
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
        val receiver = CrashReportingCheckReceiver(blockMainThread = { error("must not block") })

        assertFailsWith<CrashReportingCheckException> { receiver.onReceive(application, intent("crash")) }
    }

    @Test
    fun `the anr kind blocks the main thread longer than the foreground broadcast limit`() {
        val blocked = mutableListOf<Long>()
        val receiver = CrashReportingCheckReceiver(blockMainThread = { blocked += it })

        receiver.onReceive(application, intent("anr"))

        assertEquals(listOf(CrashReportingCheckReceiver.ANR_BLOCK_MILLIS), blocked)
        assertTrue(CrashReportingCheckReceiver.ANR_BLOCK_MILLIS > FOREGROUND_BROADCAST_LIMIT_MILLIS)
    }

    @Test
    fun `an unknown or missing kind neither throws nor blocks`() {
        val blocked = mutableListOf<Long>()
        val receiver = CrashReportingCheckReceiver(blockMainThread = { blocked += it })

        receiver.onReceive(application, intent("other"))
        receiver.onReceive(application, intent(null))

        assertTrue(blocked.isEmpty())
    }

    private companion object {
        const val FOREGROUND_BROADCAST_LIMIT_MILLIS = 10_000L
    }
}
