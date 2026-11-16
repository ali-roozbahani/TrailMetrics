package dev.roozbahani.trailmetrics.data.local.dao

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.TRACKING_SESSION_ID
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionPlanPointEntity

/**
 * The route the in-progress session was started on. The points go with their session row: deleting it
 * (`TrackingSessionDao.clear`) deletes them (the foreign key's `ON DELETE CASCADE`).
 */
@Dao
interface TrackingSessionPlanDao {

    @Insert
    suspend fun insert(points: List<TrackingSessionPlanPointEntity>)

    @Query("SELECT * FROM tbl_tracking_session_plan_points WHERE sessionId = $TRACKING_SESSION_ID ORDER BY sequence")
    suspend fun getAll(): List<TrackingSessionPlanPointEntity>

    @Query("SELECT COUNT(*) FROM tbl_tracking_session_plan_points WHERE sessionId = $TRACKING_SESSION_ID")
    suspend fun count(): Int

    @Query("DELETE FROM tbl_tracking_session_plan_points WHERE sessionId = $TRACKING_SESSION_ID")
    suspend fun deleteAll()
}
