package dev.roozbahani.trailmetrics

import android.Manifest
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
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
 * leaves a live or stored session behind: the next test would find it (`tm-testing`, "Instrumented tests").
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
        device.pressHome()
        manager.start(Coordinates(LATITUDE, LONGITUDE), ActivityType.Running)
    }

    override fun after() {
        runBlocking { manager.discard() }
        device.pressHome()
    }

    /** A bounded poll, never a fixed sleep: fails with [message] when [condition] is still false after [timeoutMs]. */
    fun eventually(message: String, timeoutMs: Long = WAIT_MS, condition: () -> Boolean) {
        val deadline = System.nanoTime() + timeoutMs * NANOS_PER_MILLI
        while (System.nanoTime() < deadline) {
            if (condition()) return
            Thread.sleep(POLL_MS)
        }
        throw AssertionError(message)
    }

    /**
     * Clicks the first node of the notification shade that matches [selector], found and clicked inside one
     * bounded poll. The service re-posts its notification, which replaces the nodes the shade shows, so a node
     * found a moment ago can be stale at the click (`StaleObjectException`); that is "not clickable yet", the
     * next poll finds the new node. It is not a retry of the test: the tap happens once.
     */
    fun clickInShade(selector: BySelector, message: String) {
        eventually(message) {
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
        private const val NANOS_PER_MILLI = 1_000_000L
        private const val LATITUDE = 47.0
        private const val LONGITUDE = 8.0
    }
}
