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
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

class TrackingService : Service(), KoinComponent {

    private val trackingSessionManager by inject<TrackingSessionManager>()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // TODO: startForeground(NOTIFICATION_ID, buildNotification(...))
        // TODO: start observing trackingSessionManager.currentState
        // TODO: Handle intent?.action for Stop btn of notification
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        // TODO: cancel the coroutine scope of this service
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

    private fun formatDistance(meters: Double): String {
        return if (meters >= 1000) {
            "%.1f km".format(meters / 1000)
        } else {
            "${meters.toInt()} m"
        }
    }

    private companion object {
        const val NOTIFICATION_ID: Int = 1
        const val CHANNEL_ID = "tracking_channel"
        const val ACTION_STOP = "dev.roozbahani.trailmetrics.action.STOP_TRACKING"
    }
}
