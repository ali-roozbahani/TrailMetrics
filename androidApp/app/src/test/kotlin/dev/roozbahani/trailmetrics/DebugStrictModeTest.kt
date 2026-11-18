package dev.roozbahani.trailmetrics

import android.app.Application
import android.content.pm.ApplicationInfo
import android.os.StrictMode
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

/** The StrictMode policies are active for a debuggable build and absent for a release build. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class DebugStrictModeTest {

    @Before
    fun setUp() = clearPolicies()

    // StrictMode's policies are process-wide: leave them as a test found them.
    @After
    fun tearDown() = clearPolicies()

    private fun clearPolicies() {
        StrictMode.setThreadPolicy(StrictMode.ThreadPolicy.LAX)
        StrictMode.setVmPolicy(StrictMode.VmPolicy.LAX)
    }

    private fun applicationInfo(debuggable: Boolean) =
        ApplicationInfo().apply { flags = if (debuggable) ApplicationInfo.FLAG_DEBUGGABLE else 0 }

    @Test
    fun `a debug build runs with the thread policy and the VM policy`() {
        installDebugStrictMode(applicationInfo(debuggable = true))

        assertEquals(debugThreadPolicy().toString(), StrictMode.getThreadPolicy().toString())
        assertEquals(debugVmPolicy().toString(), StrictMode.getVmPolicy().toString())
        assertNotEquals(StrictMode.ThreadPolicy.LAX.toString(), StrictMode.getThreadPolicy().toString())
        assertNotEquals(StrictMode.VmPolicy.LAX.toString(), StrictMode.getVmPolicy().toString())
    }

    @Test
    fun `the debug policies log and never kill the process`() {
        val death = StrictMode.VmPolicy.Builder().detectLeakedClosableObjects().penaltyDeath().build()

        assertNotEquals(death.toString(), debugVmPolicy().toString())
        // The reference of the same detectors with only the log penalty is exactly the installed policy.
        val logOnly = StrictMode.VmPolicy.Builder()
            .detectLeakedClosableObjects()
            .detectActivityLeaks()
            .detectLeakedSqlLiteObjects()
            .penaltyLog()
            .build()
        assertEquals(logOnly.toString(), debugVmPolicy().toString())
    }

    @Test
    fun `a release build has no StrictMode policy`() {
        installDebugStrictMode(applicationInfo(debuggable = false))

        assertEquals(StrictMode.ThreadPolicy.LAX.toString(), StrictMode.getThreadPolicy().toString())
        assertEquals(StrictMode.VmPolicy.LAX.toString(), StrictMode.getVmPolicy().toString())
    }
}
