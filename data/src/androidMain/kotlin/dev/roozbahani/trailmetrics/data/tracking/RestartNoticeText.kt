package dev.roozbahani.trailmetrics.data.tracking

import android.content.Context
import dev.roozbahani.trailmetrics.data.R
import dev.roozbahani.trailmetrics.domain.util.formatDistance

/** The text of [notice], from the string resources of `data` (`restart_notice_*`). */
internal fun restartNoticeText(context: Context, notice: RestartNotice): String = when (notice) {
    is RestartNotice.Paused ->
        context.getString(R.string.restart_notice_paused, formatDistance(notice.distanceMeters))
    RestartNotice.Finished -> context.getString(R.string.restart_notice_finished)
    RestartNotice.RestoreFailed -> context.getString(R.string.restart_notice_restore_failed)
}
