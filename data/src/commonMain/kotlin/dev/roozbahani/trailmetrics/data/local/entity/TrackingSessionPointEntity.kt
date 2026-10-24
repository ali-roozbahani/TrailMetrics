package dev.roozbahani.trailmetrics.data.local.entity

import androidx.room3.Entity

/** Point number [sequence] (from 0, in recorded order) of the path of session [sessionId]. */
@Entity(tableName = "tbl_tracking_session_points", primaryKeys = ["sessionId", "sequence"])
data class TrackingSessionPointEntity(
    val sessionId: Int,
    val sequence: Int,
    val latitude: Double,
    val longitude: Double
)
