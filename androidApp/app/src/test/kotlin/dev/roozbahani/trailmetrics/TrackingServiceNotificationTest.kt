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
import dev.roozbahani.trailmetrics.data.di.trackingServiceScopeQualifier
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
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
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
@OptIn(ExperimentalCoroutinesApi::class) // the test dispatchers have no stable replacement
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class TrackingServiceNotificationTest {

    private val application: Application = Robolectric.buildActivity(MainActivity::class.java).get().application

    // The scope the service gets from Koin (`trackingServiceScopeQualifier`): on a test dispatcher, so the service's
    // work runs on the test thread, inside the test, and not on a Default thread that outlives it.
    private val scheduler = TestCoroutineScheduler()
    private var serviceScope: CoroutineScope = CoroutineScope(SupervisorJob() + UnconfinedTestDispatcher(scheduler))

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
            scope = CoroutineScope(SupervisorJob() + UnconfinedTestDispatcher(scheduler))
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

    // The services a test started: destroyed before Koin stops, which cancels the scope they got from it.
    private val startedServices = mutableListOf<ServiceController<TrackingService>>()

    @After
    fun tearDown() {
        startedServices.forEach { it.destroy() }
        stopKoin()
    }

    private fun foregroundNotification(): Notification {
        val controller = Robolectric.buildService(TrackingService::class.java, Intent()).create()
        startedServices += controller
        controller.get().onStartCommand(Intent(), 0, 1)
        return assertNotNull(shadowOf(controller.get()).lastForegroundNotification)
    }

    @Test
    fun `the service observes the session on the scope Koin gives it and cancels that scope when destroyed`() {
        serviceScope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(scheduler))
        val controller = Robolectric.buildService(TrackingService::class.java, Intent()).create()
        startedServices += controller

        controller.get().onStartCommand(Intent(), 0, 1)

        // Launched on the injected dispatcher and not yet run: the dispatcher is the test's, not Default.
        assertEquals(1, serviceScope.coroutineContext.job.children.count())
        scheduler.runCurrent()
        assertTrue(serviceScope.isActive)

        controller.destroy()

        assertFalse(serviceScope.isActive)
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
