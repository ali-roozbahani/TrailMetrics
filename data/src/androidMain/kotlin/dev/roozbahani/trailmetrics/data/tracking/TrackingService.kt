package dev.roozbahani.trailmetrics.data.tracking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import dev.roozbahani.trailmetrics.data.R
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

class TrackingService : LifecycleService(), KoinComponent {

    // Not the manager itself: the first one to ask for it in a new process builds the database, off the main thread.
    private val lazyTrackingSessionManager by inject<OffMainLazy<TrackingSessionManager>>()

    private val logger by inject<Logger>()

    private var trackingStateObservationJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        startForeground(NOTIFICATION_ID, buildNotification(TrackingState.Idle))
        if (intent == null) {
            // The system restarted the service after the process died: there is nothing to observe until
            // the stored session is restored, and it may turn out there is nothing at all.
            restoreAfterRestart()
        } else {
            getSystemService(NotificationManager::class.java).cancel(RESTORED_NOTIFICATION_ID)
            observeTrackingState()
        }

        return START_STICKY
    }

    private fun restoreAfterRestart() {
        trackingStateObservationJob?.cancel()
        trackingStateObservationJob = lifecycleScope.launch {
            handleRestart({ lazyTrackingSessionManager.get().restore() }, logger, restartEffects)
        }
    }

    private val restartEffects = object : RestartEffects {
        override fun stopService() {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }

        override fun leaveNotice(notice: RestartNotice) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            val text = restartNoticeText(this@TrackingService, notice)
            val notification =
                buildRestoredNotification(this@TrackingService, CHANNEL_ID, R.drawable.ic_notif_location, text)
            getSystemService(NotificationManager::class.java).notify(RESTORED_NOTIFICATION_ID, notification)
            stopSelf()
        }

        override suspend fun keepTracking() = collectTrackingState()
    }

    private fun observeTrackingState() {
        trackingStateObservationJob?.cancel()
        trackingStateObservationJob = lifecycleScope.launch { collectTrackingState() }
    }

    private suspend fun collectTrackingState() {
        lazyTrackingSessionManager.get().currentState.collect { state ->
            val notification = buildNotification(state)
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.notify(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        // The lifecycle cancels lifecycleScope here, and the scope runs on the main thread, the thread of this
        // callback: no notify() is in flight afterwards, so nothing below can be undone by a late one.
        super.onDestroy()
        stopForeground(STOP_FOREGROUND_REMOVE)

        // Only the foreground notification: RESTORED_NOTIFICATION_ID outlives the service on purpose, it is
        // the one a restart leaves for the user to tap. stopForeground removes the foreground notification, as the
        // system expects of a service that ends; this cancel covers one that a state update posted on its own.
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.cancel(NOTIFICATION_ID)
    }

    override fun onBind(intent: Intent): IBinder? {
        super.onBind(intent)
        return null
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.tracking_notification_channel),
            NotificationManager.IMPORTANCE_LOW
        )
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(state: TrackingState): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.tracking_notification_title))
            .setContentText(trackingNotificationText(this, state))
            .setSmallIcon(R.drawable.ic_notif_location)
            .setContentIntent(buildOpenTrackingPendingIntent())
            .addAction(0, getString(R.string.tracking_notification_stop), buildStopPendingIntent())
            .setOngoing(true)
            .build()
    }

    // Targets the app's launcher Activity (MainActivity, in the androidApp/app module —
    // not referenced directly here, since `data` can't depend on `app`) rather than this
    // Service, so tapping Stop matches the in-app Stop button's result exactly: it stops
    // the session AND brings Route to the front, whether the app is foregrounded,
    // backgrounded, or not running at all. MainActivity looks for ACTION_STOP_TRACKING to
    // drive both the stop call and the navigation. That Activity is exported (it is the launcher), so the
    // intent carries the secret of StopTrackingAuthorization: without it any app could send the same action.
    private fun buildStopPendingIntent(): PendingIntent {
        val stopIntent = launchIntent(this).apply {
            action = ACTION_STOP_TRACKING
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        StopTrackingAuthorization.authorize(stopIntent)
        return PendingIntent.getActivity(
            this, 0, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    // The body of the notification brings the running session to the front. MainActivity reads
    // ACTION_OPEN_TRACKING and navigates to the Tracking screen. The action only navigates and changes no
    // session, so, unlike Stop, it carries no secret: any app sending it gets the screen of a session that
    // exists, nothing more. SINGLE_TOP delivers it to a running Activity (onNewIntent) instead of a second one.
    private fun buildOpenTrackingPendingIntent(): PendingIntent {
        val openIntent = launchIntent(this).apply {
            action = ACTION_OPEN_TRACKING
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            this,
            OPEN_TRACKING_REQUEST_CODE,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        const val ACTION_STOP_TRACKING = "dev.roozbahani.trailmetrics.action.STOP_TRACKING"
        const val ACTION_OPEN_TRACKING = "dev.roozbahani.trailmetrics.action.OPEN_TRACKING"
        private const val NOTIFICATION_ID: Int = 1

        // Different from NOTIFICATION_ID, so onDestroy's cancel of the foreground notification cannot remove it.
        internal const val RESTORED_NOTIFICATION_ID: Int = 2
        // Not 0 (Stop) and not 1 (the restart notice's launcher intent).
        private const val OPEN_TRACKING_REQUEST_CODE: Int = 2
        private const val CHANNEL_ID = "tracking_channel"
    }
}
