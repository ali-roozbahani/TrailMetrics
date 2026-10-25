package dev.roozbahani.trailmetrics

import android.app.Application
import android.content.Intent
import android.os.Bundle
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.data.tracking.TrackingService
import dev.roozbahani.trailmetrics.di.APPLICATION_SCOPE
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.fakes.FakeClock
import dev.roozbahani.trailmetrics.fakes.FakeLogger
import dev.roozbahani.trailmetrics.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.fakes.FakeTrackingSessionStore
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The notification's Stop intent on [MainActivity]. The Activity is only created, not shown, so no screen is
 * composed: `handleStopTrackingIntent` runs in `onCreate` and `onNewIntent`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class MainActivityStopIntentTest {

    private val scheduler = TestCoroutineScheduler()
    private val launcher = FakeTrackingServiceLauncher()
    private val store = FakeTrackingSessionStore()
    private val logger = FakeLogger()
    private val uncaught = mutableListOf<Throwable>()

    @OptIn(ExperimentalCoroutinesApi::class) // StandardTestDispatcher has no stable replacement
    @Before
    fun setUp() {
        val dispatcher = StandardTestDispatcher(scheduler)
        // Without a handler an uncaught failure of the scope would not fail the test: it is collected here.
        val handler = CoroutineExceptionHandler { _, e -> uncaught += e }
        val applicationScope = CoroutineScope(SupervisorJob() + dispatcher + handler)
        val manager = TrackingSessionManager(
            locationRepository = FakeLocationRepository(),
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = launcher,
            speedCalculator = SpeedCalculator(),
            clock = FakeClock(),
            logger = FakeLogger(),
            trackingSessionStore = store,
            scope = CoroutineScope(SupervisorJob() + dispatcher)
        )
        manager.start(Coordinates(47.0, 8.0), ActivityType.Running)
        scheduler.runCurrent()
        startKoin {
            modules(
                module {
                    single { manager }
                    single<Logger> { this@MainActivityStopIntentTest.logger }
                    single<CoroutineScope>(APPLICATION_SCOPE) { applicationScope }
                }
            )
        }
    }

    @After
    fun tearDown() {
        stopKoin()
    }

    private fun stopIntent() = Intent(TrackingService.ACTION_STOP_TRACKING)

    @Test
    fun `the Stop intent discards the session once`() {
        Robolectric.buildActivity(MainActivity::class.java, stopIntent()).create()
        scheduler.advanceUntilIdle()

        assertEquals(1, launcher.stopCalls)
        assertEquals(1, store.clearCalls)
        assertTrue(uncaught.isEmpty())
    }

    @Test
    fun `a Stop intent delivered to a running Activity discards the session once`() {
        val controller = Robolectric.buildActivity(MainActivity::class.java).create()
        scheduler.advanceUntilIdle()
        assertEquals(0, launcher.stopCalls)

        controller.newIntent(stopIntent())
        scheduler.advanceUntilIdle()

        assertEquals(1, launcher.stopCalls)
        assertEquals(1, store.clearCalls)
    }

    @Test
    fun `a failing discard is logged and not thrown`() {
        launcher.stopFailure = IllegalStateException("service gone")

        Robolectric.buildActivity(MainActivity::class.java, stopIntent()).create()
        scheduler.advanceUntilIdle()

        assertEquals(1, launcher.stopCalls)
        assertTrue(uncaught.isEmpty())
        assertEquals(1, logger.messages.size)
        assertTrue("service gone" in logger.messages.single())
    }

    @Test
    fun `a recreated Activity does not discard again`() {
        val first = Robolectric.buildActivity(MainActivity::class.java, stopIntent()).create()
        scheduler.advanceUntilIdle()
        assertEquals(1, launcher.stopCalls)
        // What the system does on rotation: the state is saved, the Activity is destroyed and a new one is
        // created from that state, still holding the intent of the first launch.
        val savedState = Bundle()
        first.saveInstanceState(savedState)
        first.pause().stop().destroy()

        Robolectric.buildActivity(MainActivity::class.java, stopIntent()).create(savedState)
        scheduler.advanceUntilIdle()

        assertEquals(1, launcher.stopCalls)
        assertEquals(1, store.clearCalls)
    }

    @Test
    fun `an Activity started without the Stop action discards nothing`() {
        Robolectric.buildActivity(MainActivity::class.java, Intent(Intent.ACTION_MAIN)).create()
        scheduler.advanceUntilIdle()

        assertEquals(0, launcher.stopCalls)
        assertEquals(0, store.clearCalls)
    }
}
