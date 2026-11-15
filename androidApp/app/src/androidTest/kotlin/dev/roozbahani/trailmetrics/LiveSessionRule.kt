package dev.roozbahani.trailmetrics

import android.Manifest
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import kotlinx.coroutines.runBlocking
import org.junit.rules.ExternalResource
import org.koin.core.context.GlobalContext

/**
 * Starts one real tracking session before each test, with no Activity on screen, and discards it
 * afterwards. The app's own process runs the real Koin graph (`TrailMetricsApplication`), so the
 * session, the foreground service and its notification are the real ones. A test of this tier never
 * leaves a live or stored session behind: the next test would find it (`tm-testing`, "Rules for `androidTest`").
 */
class LiveSessionRule : ExternalResource() {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    val device: UiDevice = UiDevice.getInstance(instrumentation)
    val packageName: String = instrumentation.targetContext.packageName
    val manager: TrackingSessionManager = GlobalContext.get().get()

    override fun before() {
        listOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.POST_NOTIFICATIONS
        ).forEach { instrumentation.uiAutomation.grantRuntimePermission(packageName, it) }
        goHome()
        manager.start(Coordinates(LATITUDE, LONGITUDE), ActivityType.Running)
    }

    override fun after() {
        runBlocking { manager.discard() }
        goHome()
    }

    /**
     * Presses Home and waits until the launcher is on screen. `pressHome` returns before the transition ends, so a
     * start that follows at once can be covered by the launcher coming back to the front.
     */
    private fun goHome() {
        device.pressHome()
        val launcher = homePackage()
        if (!device.wait(Until.hasObject(By.pkg(launcher)), WAIT_MS)) {
            throw AssertionError("the launcher $launcher never came to the front. ${screenState()}")
        }
    }

    /**
     * A bounded poll, never a fixed sleep: fails with [message] when [condition] is still false after [timeoutMs].
     * The message is built at the deadline, so it can name the state the wait ended in.
     */
    fun eventually(message: () -> String, timeoutMs: Long = WAIT_MS, condition: () -> Boolean) {
        val deadline = System.nanoTime() + timeoutMs * NANOS_PER_MILLI
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(POLL_MS)
        }
        throw AssertionError(message())
    }

    // `UiDevice.launcherPackageName` names the settings app on this image, so ask the package manager for the Home activity.
    private fun homePackage(): String {
        val resolved = device.executeShellCommand(
            "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"
        ).lineSequence().map { it.trim() }.lastOrNull { it.contains('/') }
        return checkNotNull(resolved) { "no Home activity resolved" }.substringBefore('/')
    }

    /** What the system shows right now, for a failure message: the foreground package and the focused window. */
    fun screenState(): String {
        val windows = device.executeShellCommand("dumpsys window windows")
            .lineSequence()
            .filter { it.contains("mCurrentFocus") || it.contains("mFocusedApp") }
            .joinToString("; ") { it.trim() }
        val log = device.executeShellCommand("logcat -d -s ActivityTaskManager:I ActivityManager:I AndroidRuntime:E")
            .lineSequence()
            .filter { it.contains("trailmetrics") || it.contains("AndroidRuntime") }
            .toList()
            .takeLast(LOG_LINES)
            .joinToString("\n") { it.trim() }
        return "foreground package ${device.currentPackageName}; $windows\nlast log lines:\n$log"
    }

    /**
     * Clicks the first node of the notification shade that matches [selector], found and clicked inside one
     * bounded poll. The service re-posts its notification, which replaces the nodes the shade shows, so a node
     * found a moment ago can be stale at the click (`StaleObjectException`); that is "not clickable yet", the
     * next poll finds the new node. It is not a retry of the test: the tap happens once.
     */
    fun clickInShade(selector: BySelector, message: String) {
        eventually({ message }) {
            val node = device.findObject(selector) ?: return@eventually false
            try {
                node.click()
                true
            } catch (_: StaleObjectException) {
                false
            }
        }
    }

    companion object {
        const val WAIT_MS = 15_000L
        private const val POLL_MS = 100L
        private const val LOG_LINES = 25
        private const val NANOS_PER_MILLI = 1_000_000L
        private const val LATITUDE = 47.0
        private const val LONGITUDE = 8.0
    }
}
