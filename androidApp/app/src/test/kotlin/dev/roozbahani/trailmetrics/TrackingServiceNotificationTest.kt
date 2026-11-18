package dev.roozbahani.trailmetrics

import android.app.Application
import android.app.Notification
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import dev.roozbahani.trailmetrics.core.testing.FakeClock
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.data.tracking.StopTrackingAuthorization
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
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking
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
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** The tracking notification the real [TrackingService] posts: its body and its Stop button. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class TrackingServiceNotificationTest {

    private val application: Application = Robolectric.buildActivity(MainActivity::class.java).get().application

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Before
    fun setUp() {
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
                }
            )
        }
    }

    // The services a test started. `onStartCommand` launches the service's observation on `Dispatchers.Default`, which
    // resolves its dependencies from Koin when it starts. A service that is not destroyed keeps that work alive past
    // `stopKoin()`: it then fails on a Default thread ("KoinApplication has not been started"), and the next
    // `runTest` in the same JVM, in whatever class, reports it as an uncaught exception before its test.
    private val startedServices = mutableListOf<ServiceController<TrackingService>>()

    @After
    fun tearDown() {
        startedServices.forEach { controller ->
            val service = controller.get()
            controller.destroy()
            // `onDestroy` cancels the service scope, but work that is already running on a Default thread (building the
            // notification) goes on until it returns, and it needs what this test set up (the launcher activity of the
            // package manager shadow, Koin). Wait until that work is over before the test environment is torn down.
            runBlocking { serviceScope(service).coroutineContext.job.join() }
        }
        stopKoin()
    }

    // The scope is private to `data`, which has no seam for the dispatcher yet (`tm-robustness` D1,
    // `inject-dispatchers-from-di`).
    private fun serviceScope(service: TrackingService): CoroutineScope =
        TrackingService::class.java.getDeclaredField("serviceScope")
            .apply { isAccessible = true }
            .get(service) as CoroutineScope

    private fun foregroundNotification(): Notification {
        val controller = Robolectric.buildService(TrackingService::class.java, Intent()).create()
        startedServices += controller
        controller.get().onStartCommand(Intent(), 0, 1)
        return assertNotNull(shadowOf(controller.get()).lastForegroundNotification)
    }

    @Test
    fun `tapping the notification's body opens the app on the live session`() {
        val tap = shadowOf(assertNotNull(foregroundNotification().contentIntent)).savedIntent

        assertEquals(TrackingService.ACTION_OPEN_TRACKING, tap.action)
        assertEquals(application.packageName, tap.component?.packageName)
    }

    @Test
    fun `the body's intent is not the Stop and carries no secret`() {
        val tap = shadowOf(assertNotNull(foregroundNotification().contentIntent)).savedIntent

        assertFalse(tap.action == TrackingService.ACTION_STOP_TRACKING)
        assertFalse(StopTrackingAuthorization.isAuthorized(tap))
    }

    @Test
    fun `the Stop button still carries the Stop action and the secret`() {
        val stop = foregroundNotification().actions.single { it.title == "Stop" }
        val intent = shadowOf(stop.actionIntent).savedIntent

        assertEquals(TrackingService.ACTION_STOP_TRACKING, intent.action)
        assertTrue(StopTrackingAuthorization.isAuthorized(intent))
    }
}
