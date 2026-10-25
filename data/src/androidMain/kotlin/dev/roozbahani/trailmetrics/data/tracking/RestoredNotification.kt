package dev.roozbahani.trailmetrics.data.tracking

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * The Intent that opens the app's launcher Activity (`MainActivity`, in the androidApp/app module, which
 * `data` can't depend on).
 */
internal fun launchIntent(context: Context): Intent =
    checkNotNull(context.packageManager.getLaunchIntentForPackage(context.packageName)) {
        "No launcher Activity found for ${context.packageName}"
    }

/**
 * The notice a restart leaves behind: a normal notification that opens the app through its launcher
 * intent, where the stored session is offered. It is not ongoing and goes away when tapped.
 */
internal fun buildRestoredNotification(
    context: Context,
    channelId: String,
    smallIcon: Int,
    text: String
): Notification {
    val openApp = PendingIntent.getActivity(
        context,
        OPEN_APP_REQUEST_CODE,
        launchIntent(context),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    return NotificationCompat.Builder(context, channelId)
        .setContentTitle("TrailMetrics")
        .setContentText(text)
        .setSmallIcon(smallIcon)
        .setContentIntent(openApp)
        .setAutoCancel(true)
        .build()
}

// The tracking notification's Stop PendingIntent uses request code 0.
private const val OPEN_APP_REQUEST_CODE = 1
