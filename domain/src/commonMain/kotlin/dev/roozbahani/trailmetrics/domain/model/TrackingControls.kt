package dev.roozbahani.trailmetrics.domain.model

/**
 * Which tracking controls the user may use. The one place that holds these rules, for both platforms:
 * a ViewModel asks [availableControls] and shows what it says.
 *
 * - [canStart]: only from [TrackingState.Idle], and not while the stored session is still being read.
 *   A finished session that is not saved yet does not offer Start: starting would replace it.
 * - [canPause]: only while tracking.
 * - [canResume]: only while paused.
 * - [canStop]: while tracking or paused. Stop discards the session, so this is also the discard control.
 * - [canSave]: only for a finished session, which the user can save (Finish), discard or leave stored.
 * - [canDiscard]: only for a finished session, which the user can delete without saving it. A tracking or
 *   paused session is discarded through [canStop] instead; Idle has nothing to discard.
 */
data class TrackingControls(
    val canStart: Boolean,
    val canPause: Boolean,
    val canResume: Boolean,
    val canStop: Boolean,
    val canSave: Boolean,
    val canDiscard: Boolean
)

/** [isRestoring] is true until the stored session has been read; Start is not offered meanwhile. */
fun TrackingState.availableControls(isRestoring: Boolean): TrackingControls = when (this) {
    TrackingState.Idle -> TrackingControls(
        canStart = !isRestoring,
        canPause = false,
        canResume = false,
        canStop = false,
        canSave = false,
        canDiscard = false
    )
    is TrackingState.Tracking -> TrackingControls(
        canStart = false,
        canPause = true,
        canResume = false,
        canStop = true,
        canSave = false,
        canDiscard = false
    )
    is TrackingState.Paused -> TrackingControls(
        canStart = false,
        canPause = false,
        canResume = true,
        canStop = true,
        canSave = false,
        canDiscard = false
    )
    is TrackingState.Finished -> TrackingControls(
        canStart = false,
        canPause = false,
        canResume = false,
        canStop = false,
        canSave = true,
        canDiscard = true
    )
}
