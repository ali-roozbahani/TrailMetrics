package dev.roozbahani.trailmetrics.data.tracking

import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.CancellationException

/** What [TrackingService] does once a restart with no intent has restored the stored session. */
internal sealed interface RestartAction {
    /** Nothing to track or offer: remove the foreground notification and stop. */
    data object StopSilently : RestartAction

    /** A session is live in this process (only the service was killed): keep the foreground service. */
    data object KeepTracking : RestartAction

    /** The session waits for the user: post this one normal notification, then stop. */
    data class ShowNotice(val notice: RestartNotice) : RestartAction
}

/**
 * Which notice a restart leaves: a typed value, not text. Its text comes from the Android string resources
 * ([restartNoticeText]; owner decision of 2026-11-25: no user-visible text in code).
 */
internal sealed interface RestartNotice {
    /** A paused session that waits to be continued, with the distance recorded so far. */
    data class Paused(val distanceMeters: Double) : RestartNotice

    /** A finished session that is not saved yet. */
    data object Finished : RestartNotice

    /**
     * A restore that threw (owner decision of 2026-11-25: surfaced, not stopped silently). The stored session may
     * still be there: opening the app restores it again, and the app says so if that fails too.
     */
    data object RestoreFailed : RestartNotice
}

internal fun restartActionFor(restored: TrackingState): RestartAction = when (restored) {
    TrackingState.Idle -> RestartAction.StopSilently
    is TrackingState.Tracking -> RestartAction.KeepTracking
    is TrackingState.Paused -> RestartAction.ShowNotice(RestartNotice.Paused(restored.metrics.distanceMeters))
    is TrackingState.Finished -> RestartAction.ShowNotice(RestartNotice.Finished)
}

/** What [TrackingService] does for each [RestartAction]; the service implements it, a test fakes it. */
internal interface RestartEffects {
    /** Removes the foreground notification and stops the service. */
    fun stopService()

    /** Removes the foreground notification, posts [notice] as a normal notification and stops the service. */
    fun leaveNotice(notice: RestartNotice)

    /** Keeps the foreground service for the live session; returns only when the service is done. */
    suspend fun keepTracking()
}

/**
 * Restores the stored session after the system restarted the service with no intent, and does what
 * [restartActionFor] decides. A restore that throws is logged and leaves [RestartNotice.RestoreFailed]: the service
 * does not stay in the foreground with nothing to track, and the user learns that recording stopped.
 */
internal suspend fun handleRestart(restore: suspend () -> TrackingState, logger: Logger, effects: RestartEffects) {
    val action = try {
        restartActionFor(restore())
    } catch (e: CancellationException) {
        throw e
    } catch (expected: Exception) {
        logger.debug(TAG, "Restoring the session after a restart failed: $expected")
        RestartAction.ShowNotice(RestartNotice.RestoreFailed)
    }
    when (action) {
        RestartAction.StopSilently -> effects.stopService()
        RestartAction.KeepTracking -> effects.keepTracking()
        is RestartAction.ShowNotice -> effects.leaveNotice(action.notice)
    }
}

private const val TAG = "TrackingService"
