package dev.roozbahani.trailmetrics.data.tracking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import dev.roozbahani.trailmetrics.data.R
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

class TrackingService : Service(), KoinComponent {

    private val trackingSessionManager by inject<TrackingSessionManager>()

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private var trackingStateObservationJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification(TrackingState.Idle))
        observeTrackingState()

        return START_STICKY
    }

    private fun observeTrackingState() {
        trackingStateObservationJob?.cancel()
        trackingStateObservationJob = serviceScope.launch {
            trackingSessionManager.currentState.collect { state ->
                val notification = buildNotification(state)
                val notificationManager = getSystemService(NotificationManager::class.java)
                notificationManager.notify(NOTIFICATION_ID, notification)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()

        // Explicitly cancel the notification to guard against a race condition
        // where a state update calls notify() right around service teardown,
        // leaving a stale notification behind that the system doesn't auto-remove.
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.cancel(NOTIFICATION_ID)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Tracking",
            NotificationManager.IMPORTANCE_LOW
        )
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(state: TrackingState): Notification {
        val contentText = when (state) {
            is TrackingState.Tracking -> "Tracking...${formatDistance(state.metrics.distanceMeters)}"
            is TrackingState.Paused -> "Paused - ${formatDistance(state.metrics.distanceMeters)}"
            else -> "Setting up..."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("TrailMetrics")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_notif_location)
            .addAction(0, "Stop", buildStopPendingIntent())
            .setOngoing(true)
            .build()
    }

    // Targets the app's launcher Activity (MainActivity, in the androidApp/app module —
    // not referenced directly here, since `data` can't depend on `app`) rather than this
    // Service, so tapping Stop matches the in-app Stop button's result exactly: it stops
    // the session AND brings Route to the front, whether the app is foregrounded,
    // backgrounded, or not running at all. MainActivity looks for ACTION_STOP_TRACKING to
    // drive both the stop call and the navigation.
    private fun buildStopPendingIntent(): PendingIntent {
        val launchIntent = checkNotNull(packageManager.getLaunchIntentForPackage(packageName)) {
            "No launcher Activity found for $packageName"
        }
        val stopIntent = launchIntent.apply {
            action = ACTION_STOP_TRACKING
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            this, 0, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        const val ACTION_STOP_TRACKING = "dev.roozbahani.trailmetrics.action.STOP_TRACKING"
        private const val NOTIFICATION_ID: Int = 1
        private const val CHANNEL_ID = "tracking_channel"
    }
}
