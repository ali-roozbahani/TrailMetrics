package dev.roozbahani.trailmetrics

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.os.Looper
import dev.roozbahani.trailmetrics.core.testing.FakeClock
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.data.di.newTrackingServiceScope
import dev.roozbahani.trailmetrics.data.di.trackingServiceScopeQualifier
import dev.roozbahani.trailmetrics.data.tracking.TrackingService
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowNotificationManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * A `notify()` that is still running on another thread when the service is destroyed must not leave the tracking
 * notification behind. On a device the manager ends a session at the route's end and stops the service at once, so
 * the notification for the last state is built and posted on a worker thread while `onDestroy` runs on the main thread.
 * The shadow below holds a `notify()` made off the main thread until the test releases it, which is the ordering the
 * emulator logs showed (`onDestroy` and its `cancel`, then the late `notify`).
 */
@OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, shadows = [HoldsOffMainNotifyShadow::class])
class TrackingServiceTeardownTest {

    private val application: Application = Robolectric.buildActivity(MainActivity::class.java).get().application
    // The scope the app gives the service (the real factory the Koin graph binds), not one the test chooses.
    private val serviceScope = newTrackingServiceScope()

    @Before
    fun setUp() {
        HoldsOffMainNotifyShadow.reset()
        val launcherActivity = ComponentName(application.packageName, MainActivity::class.java.name)
        shadowOf(application.packageManager).run {
            addOrUpdateActivity(
                ActivityInfo().apply {
                    packageName = launcherActivity.packageName
                    name = launcherActivity.className
                }
            )
            addIntentFilterForActivity(
                launcherActivity,
                IntentFilter(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
            )
        }
        val manager = TrackingSessionManager(
            locationRepository = FakeLocationRepository(),
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = FakeTrackingServiceLauncher(),
            speedCalculator = SpeedCalculator(),
            clock = FakeClock(),
            logger = FakeLogger(),
            trackingSessionStore = FakeTrackingSessionStore(),
            scope = CoroutineScope(SupervisorJob() + UnconfinedTestDispatcher())
        )
        manager.start(Coordinates(47.0, 8.0), ActivityType.Running)
        startKoin {
            modules(
                module {
                    single { manager }
                    single<Logger> { FakeLogger() }
                    factory<CoroutineScope>(trackingServiceScopeQualifier) { serviceScope }
                }
            )
        }
    }

    @After
    fun tearDown() {
        HoldsOffMainNotifyShadow.release()
        serviceScope.cancel()
        stopKoin()
    }

    @Test
    fun `a notification still being posted off the main thread when the service is destroyed does not outlive it`() {
        val controller = Robolectric.buildService(TrackingService::class.java, Intent()).create()
        controller.get().onStartCommand(Intent(), 0, 1)
        // Before the fix the scope runs on Dispatchers.Default and the service's notify is held on a worker thread;
        // after it, the scope runs on the main thread and nothing is held (this wait then times out, which is fine).
        HoldsOffMainNotifyShadow.awaitHeld(timeoutMs = 2_000)

        controller.destroy()
        HoldsOffMainNotifyShadow.release()
        // What the dispatcher of the service's scope ran off the main thread has finished by now.
        Thread.sleep(200)
        shadowOf(Looper.getMainLooper()).idle()

        val notificationManager = application.getSystemService(NotificationManager::class.java)
        assertEquals(
            emptyList(),
            shadowOf(notificationManager).allNotifications.map { it.extras.getString(Notification.EXTRA_TEXT) },
            "the tracking notification was posted after the service's onDestroy cancelled it"
        )
    }

    @Test
    fun `the service posts its notification on the main thread`() {
        val controller = Robolectric.buildService(TrackingService::class.java, Intent()).create()
        controller.get().onStartCommand(Intent(), 0, 1)
        shadowOf(Looper.getMainLooper()).idle()
        HoldsOffMainNotifyShadow.release()
        Thread.sleep(200)

        assertTrue(
            HoldsOffMainNotifyShadow.offMainNotifyCount == 0,
            "notify() ran ${HoldsOffMainNotifyShadow.offMainNotifyCount} time(s) off the main thread"
        )
        controller.destroy()
    }

    @Test
    fun `destroying the service removes its foreground notification`() {
        val controller = Robolectric.buildService(TrackingService::class.java, Intent()).create()
        controller.get().onStartCommand(Intent(), 0, 1)
        shadowOf(Looper.getMainLooper()).idle()

        controller.destroy()

        assertTrue(shadowOf(controller.get()).notificationShouldRemoved, "the foreground notification was not removed")
    }
}

/** Counts the `notify()` calls made off the main thread and holds each one until [release]. */
@Implements(NotificationManager::class)
class HoldsOffMainNotifyShadow : ShadowNotificationManager() {

    @Implementation
    @Synchronized
    override fun notify(tag: String?, id: Int, notification: Notification?) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            offMainNotifyCount++
            held.countDown()
            gate.await(10, TimeUnit.SECONDS)
        }
        super.notify(tag, id, notification)
    }

    companion object {
        @Volatile var offMainNotifyCount = 0
        private var held = CountDownLatch(1)
        private var gate = CountDownLatch(1)

        fun reset() {
            offMainNotifyCount = 0
            held = CountDownLatch(1)
            gate = CountDownLatch(1)
        }

        fun awaitHeld(timeoutMs: Long) = held.await(timeoutMs, TimeUnit.MILLISECONDS)

        fun release() = gate.countDown()
    }
}
