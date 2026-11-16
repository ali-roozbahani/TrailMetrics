package dev.roozbahani.trailmetrics.data.local.entity

import androidx.room3.Entity
import androidx.room3.ForeignKey

/**
 * Point number [sequence] (from 0, in route order) of the route that session [sessionId] was started on.
 * The points belong to their session: deleting the session row deletes them.
 */
@Entity(
    tableName = "tbl_tracking_session_plan_points",
    primaryKeys = ["sessionId", "sequence"],
    foreignKeys = [
        ForeignKey(
            entity = TrackingSessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["sessionId"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class TrackingSessionPlanPointEntity(
    val sessionId: Int,
    val sequence: Int,
    val latitude: Double,
    val longitude: Double
)
