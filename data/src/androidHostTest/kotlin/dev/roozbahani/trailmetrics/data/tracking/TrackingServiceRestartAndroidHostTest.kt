package dev.roozbahani.trailmetrics.data.tracking

import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.content.pm.ActivityInfo
import androidx.test.core.app.ApplicationProvider
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The real [TrackingService] on Robolectric, restarted with no intent, over a real session manager. */
@RunWith(org.robolectric.RobolectricTestRunner::class)
@Config(sdk = [35])
class TrackingServiceRestartAndroidHostTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val notifications get() = shadowOf(context.getSystemService(NotificationManager::class.java))
    private val scope = CoroutineScope(SupervisorJob())
    private val store = FakeStore()
    private val testLogger = RecordingLogger()

    private class RecordingLogger : Logger {
        val messages = mutableListOf<String>()

        override fun debug(tag: String, message: String) {
            messages += message
        }
    }

    private class FakeStore : TrackingSessionStore {
        @Volatile var stored: StoredTrackingSession? = null

        @Volatile var loadFailure: Exception? = null

        override suspend fun save(session: StoredTrackingSession) = Unit

        override suspend fun load(): StoredTrackingSession? {
            loadFailure?.let { throw it }
            return stored
        }

        override suspend fun clear() = Unit
    }

    private val manager = TrackingSessionManager(
        locationRepository = object : LocationRepository {
            override suspend fun getCurrentLocation(): Result<Coordinates> = Result.failure(IllegalStateException())

            override fun observeLocationUpdates(): Flow<LocationUpdate> = emptyFlow()
        },
        updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
        trackingServiceLauncher = object : TrackingServiceLauncher {
            override fun start() = Unit

            override fun stop() = Unit
        },
        speedCalculator = SpeedCalculator(),
        clock = object : Clock {
            override fun nowMillis() = 0L

            override fun elapsedRealtimeMillis() = 0L
        },
        logger = testLogger,
        trackingSessionStore = store,
        scope = scope
    )

    @Before
    fun setUp() {
        startKoin {
            modules(
                module {
                    single { manager }
                    single<Logger> { testLogger }
                }
            )
        }
        val launcherActivity = ComponentName(context.packageName, "${context.packageName}.MainActivity")
        val packageManager = shadowOf(context.packageManager)
        packageManager.addOrUpdateActivity(
            ActivityInfo().apply {
                packageName = launcherActivity.packageName
                name = launcherActivity.className
            }
        )
        packageManager.addIntentFilterForActivity(
            launcherActivity,
            IntentFilter(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
        )
    }

    @After
    fun tearDown() {
        stopKoin()
        scope.cancel()
    }

    private fun metrics() = TrackingMetrics(
        elapsedMillis = 60_000L,
        lastUpdateElapsedRealtimeMillis = 60_000L,
        distanceMeters = 850.0,
        path = listOf(Coordinates(51.336, 12.388))
    )

    private fun restartedService(): TrackingService {
        val controller = Robolectric.buildService(TrackingService::class.java).create()
        controller.get().onStartCommand(null, 0, 1)
        return controller.get()
    }

    private fun awaitStopped(service: TrackingService) = await { shadowOf(service).isStoppedBySelf }

    private fun await(condition: () -> Boolean) = runBlocking {
        withTimeout(TIMEOUT_MILLIS) { while (!condition()) delay(POLL_MILLIS) }
    }

    @Test
    fun `a restart with a stored Paused session leaves one normal notification and stops the service`() {
        store.stored = StoredTrackingSession(TrackingState.Paused(metrics()), null, null)

        val service = restartedService()
        awaitStopped(service)

        val notice = assertNotNull(notifications.getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
        assertEquals("Paused - 850 m, tap to continue", notice.extras.getString(Notification.EXTRA_TEXT))
        assertTrue(notice.flags and Notification.FLAG_AUTO_CANCEL != 0)
        assertEquals(0, notice.flags and Notification.FLAG_ONGOING_EVENT)
        assertNotNull(notice.contentIntent)
        assertEquals(TrackingState.Paused(metrics()), manager.currentState.value)
    }

    @Test
    fun `a restart with a stored Finished session offers to save it`() {
        store.stored = StoredTrackingSession(TrackingState.Finished(metrics()), null, null)

        awaitStopped(restartedService())

        val notice = assertNotNull(notifications.getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
        assertEquals("Finished - not saved, tap to save", notice.extras.getString(Notification.EXTRA_TEXT))
    }

    @Test
    fun `a restart with no stored session stops the service and leaves no notification`() {
        awaitStopped(restartedService())

        assertNull(notifications.getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
    }

    @Test
    fun `a restart whose restore throws stops the service and leaves no notification`() {
        store.loadFailure = IllegalStateException("unreadable")

        awaitStopped(restartedService())

        assertNull(notifications.getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
        assertTrue(testLogger.messages.any { "unreadable" in it })
    }

    @Test
    fun `destroying the service does not cancel the restart notice`() {
        store.stored = StoredTrackingSession(TrackingState.Paused(metrics()), null, null)
        val service = restartedService()
        awaitStopped(service)

        service.onDestroy()

        assertNotNull(notifications.getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
    }

    @Test
    fun `a start with an intent keeps today's behavior and clears an older restart notice`() {
        store.stored = StoredTrackingSession(TrackingState.Paused(metrics()), null, null)
        awaitStopped(restartedService())
        assertNotNull(notifications.getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
        val controller = Robolectric.buildService(TrackingService::class.java).create()

        controller.get().onStartCommand(Intent(context, TrackingService::class.java), 0, 2)

        assertNull(notifications.getNotification(TrackingService.RESTORED_NOTIFICATION_ID))
        assertEquals(false, shadowOf(controller.get()).isStoppedBySelf)
        // The service observes the restored session: wait for it, so it is not torn down mid-start.
        await {
            notifications.getNotification(1)?.extras?.getString(Notification.EXTRA_TEXT) == "Paused - 850 m"
        }
        controller.get().onDestroy()
    }

    private companion object {
        const val TIMEOUT_MILLIS = 30_000L
        const val POLL_MILLIS = 10L
    }
}
