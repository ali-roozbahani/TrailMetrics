package dev.roozbahani.trailmetrics.data.tracking

import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import kotlinx.coroutines.CancellationException

/** What [TrackingService] does once a restart with no intent has restored the stored session. */
internal sealed interface RestartAction {
    /** Nothing to track or offer: remove the foreground notification and stop. */
    data object StopSilently : RestartAction

    /** A session is live in this process (only the service was killed): keep the foreground service. */
    data object KeepTracking : RestartAction

    /** The session waits for the user: post this one normal notification, then stop. */
    data class ShowNotice(val text: String) : RestartAction
}

internal fun restartActionFor(restored: TrackingState): RestartAction = when (restored) {
    TrackingState.Idle -> RestartAction.StopSilently
    is TrackingState.Tracking -> RestartAction.KeepTracking
    is TrackingState.Paused ->
        RestartAction.ShowNotice("Paused - ${formatDistance(restored.metrics.distanceMeters)}, tap to continue")
    is TrackingState.Finished -> RestartAction.ShowNotice("Finished - not saved, tap to save")
}

/** What [TrackingService] does for each [RestartAction]; the service implements it, a test fakes it. */
internal interface RestartEffects {
    /** Removes the foreground notification and stops the service. */
    fun stopService()

    /** Removes the foreground notification, posts [text] as a normal notification and stops the service. */
    fun leaveNotice(text: String)

    /** Keeps the foreground service for the live session; returns only when the service is done. */
    suspend fun keepTracking()
}

/**
 * Restores the stored session after the system restarted the service with no intent, and does what
 * [restartActionFor] decides. A restore that throws is logged and ends like an empty one: the service
 * must not stay in the foreground with nothing to track.
 */
internal suspend fun handleRestart(restore: suspend () -> TrackingState, logger: Logger, effects: RestartEffects) {
    val action = try {
        restartActionFor(restore())
    } catch (e: CancellationException) {
        throw e
    } catch (expected: Exception) {
        logger.debug(TAG, "Restoring the session after a restart failed: $expected")
        RestartAction.StopSilently
    }
    when (action) {
        RestartAction.StopSilently -> effects.stopService()
        RestartAction.KeepTracking -> effects.keepTracking()
        is RestartAction.ShowNotice -> effects.leaveNotice(action.text)
    }
}

private const val TAG = "TrackingService"
