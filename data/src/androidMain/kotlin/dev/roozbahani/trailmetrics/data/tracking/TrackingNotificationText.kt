package dev.roozbahani.trailmetrics.data.tracking

import android.content.Context
import dev.roozbahani.trailmetrics.data.R
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.formatDistance

/**
 * The text of the tracking notification for [state], from the string resources of `data`
 * (`tracking_notification_*`).
 */
internal fun trackingNotificationText(context: Context, state: TrackingState): String = when (state) {
    is TrackingState.Tracking ->
        context.getString(R.string.tracking_notification_tracking, formatDistance(state.metrics.distanceMeters))
    is TrackingState.Paused ->
        context.getString(R.string.tracking_notification_paused, formatDistance(state.metrics.distanceMeters))
    is TrackingState.Idle, is TrackingState.Finished -> context.getString(R.string.tracking_notification_setting_up)
}
