package dev.roozbahani.trailmetrics.data.tracking

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher

class AndroidTrackingServiceLauncher(
    private val context: Context
) : TrackingServiceLauncher {
    override fun start() {
        val intent = Intent(context, TrackingService::class.java)
        ContextCompat.startForegroundService(context, intent)
    }

    override fun stop() {
        // The session is over or discarded: the notice a restart left for it no longer applies.
        context.getSystemService(NotificationManager::class.java).cancel(TrackingService.RESTORED_NOTIFICATION_ID)
        context.stopService(Intent(context, TrackingService::class.java))
    }
}
