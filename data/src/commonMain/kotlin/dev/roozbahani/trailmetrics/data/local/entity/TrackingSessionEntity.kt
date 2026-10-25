package dev.roozbahani.trailmetrics.data.local.entity

import androidx.room3.Entity
import androidx.room3.PrimaryKey

/**
 * The one in-progress session: always the row with [TRACKING_SESSION_ID].
 * Its path is in [TrackingSessionPointEntity].
 */
@Entity(tableName = "tbl_tracking_session")
data class TrackingSessionEntity(
    @PrimaryKey val id: Int = TRACKING_SESSION_ID,
    /** One of [STATE_TRACKING], [STATE_PAUSED], [STATE_FINISHED]. */
    val stateKind: String,
    val elapsedMillis: Long,
    val lastUpdateElapsedRealtimeMillis: Long,
    val distanceMeters: Double,
    val currentSpeedMetersPerSecond: Float?,
    val savedAtEpochMillis: Long,
    /** The [dev.roozbahani.trailmetrics.domain.model.ActivityType] name; null when never known. */
    val activityType: String? = null
) {
    companion object {
        const val TRACKING_SESSION_ID = 1
        const val STATE_TRACKING = "Tracking"
        const val STATE_PAUSED = "Paused"
        const val STATE_FINISHED = "Finished"
    }
}
