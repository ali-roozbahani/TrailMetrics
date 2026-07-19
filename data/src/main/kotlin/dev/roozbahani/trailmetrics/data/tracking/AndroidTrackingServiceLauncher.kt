package dev.roozbahani.trailmetrics.data.tracking

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
        context.stopService(Intent(context, TrackingService::class.java))
    }
}