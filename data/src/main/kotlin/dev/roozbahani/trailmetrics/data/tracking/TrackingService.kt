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
        if (intent?.action == ACTION_STOP) {
            trackingSessionManager.stop()
            return START_NOT_STICKY
        }

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

        val stopIntent = Intent(this, TrackingService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("TrailMetrics")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_notif_location)
            .addAction(0, "Stop", stopPendingIntent)
            .setOngoing(true)
            .build()
    }

    private companion object {
        const val NOTIFICATION_ID: Int = 1
        const val CHANNEL_ID = "tracking_channel"
        const val ACTION_STOP = "dev.roozbahani.trailmetrics.action.STOP_TRACKING"
    }
}
