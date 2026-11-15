package dev.roozbahani.trailmetrics.data.tracking

import android.content.Intent
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Tells the notification's Stop apart from any other intent with the same action.
 *
 * The launcher Activity is exported, so any app can send it an intent with [TrackingService.ACTION_STOP_TRACKING].
 * The Stop button's `PendingIntent` carries a secret extra that only this process knows: the extras of a
 * `PendingIntent` are held by the system and readable by no other app. The secret lives in memory for the life of
 * the process. A restarted service builds its notification, and so its Stop, with the new process's secret.
 */
object StopTrackingAuthorization {
    private const val EXTRA_STOP_TOKEN = "dev.roozbahani.trailmetrics.extra.STOP_TOKEN"
    private const val TOKEN_BYTES = 16

    private val token: String by lazy {
        ByteArray(TOKEN_BYTES).also(SecureRandom()::nextBytes).joinToString("") { "%02x".format(it) }
    }

    /** Marks [intent] as sent by this app's own Stop button. */
    fun authorize(intent: Intent): Intent = intent.putExtra(EXTRA_STOP_TOKEN, token)

    /** True only for an intent that went through [authorize] in this process. */
    fun isAuthorized(intent: Intent?): Boolean {
        val presented = intent?.getStringExtra(EXTRA_STOP_TOKEN) ?: return false
        return MessageDigest.isEqual(presented.toByteArray(), token.toByteArray())
    }
}
