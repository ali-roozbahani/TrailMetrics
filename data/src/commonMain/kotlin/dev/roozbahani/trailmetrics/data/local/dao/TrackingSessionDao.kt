package dev.roozbahani.trailmetrics.data.local.dao

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query
import androidx.room3.Transaction
import androidx.room3.Upsert
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity.Companion.TRACKING_SESSION_ID
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionPointEntity
import dev.roozbahani.trailmetrics.domain.model.Coordinates

@Dao
interface TrackingSessionDao {

    /**
     * Writes [session] and the points of [path] that are not stored yet, in one transaction. The
     * stored points are kept when they are a prefix of [path] (checked by their count and last
     * point); otherwise (a new session replaced the old one) the stored points are replaced.
     */
    @Transaction
    suspend fun save(session: TrackingSessionEntity, path: List<Coordinates>) {
        val storedCount = countPoints()
        val lastStored = if (storedCount in 1..path.size) getPoint(storedCount - 1) else null
        val isPrefix = lastStored != null && lastStored.isAt(path[storedCount - 1])
        val keep = if (isPrefix) storedCount else 0
        if (keep < storedCount) deletePointsFrom(keep)
        insertPoints(
            path.drop(keep).mapIndexed { index, point ->
                TrackingSessionPointEntity(TRACKING_SESSION_ID, keep + index, point.latitude, point.longitude)
            }
        )
        upsertSession(session)
    }

    @Transaction
    suspend fun clear() {
        deletePointsFrom(0)
        deleteSession()
    }

    @Upsert
    suspend fun upsertSession(session: TrackingSessionEntity)

    @Insert
    suspend fun insertPoints(points: List<TrackingSessionPointEntity>)

    @Query("SELECT * FROM tbl_tracking_session WHERE id = $TRACKING_SESSION_ID")
    suspend fun getSession(): TrackingSessionEntity?

    @Query("SELECT * FROM tbl_tracking_session_points WHERE sessionId = $TRACKING_SESSION_ID ORDER BY sequence")
    suspend fun getPoints(): List<TrackingSessionPointEntity>

    @Query("SELECT * FROM tbl_tracking_session_points WHERE sessionId = $TRACKING_SESSION_ID AND sequence = :sequence")
    suspend fun getPoint(sequence: Int): TrackingSessionPointEntity?

    @Query("SELECT COUNT(*) FROM tbl_tracking_session_points WHERE sessionId = $TRACKING_SESSION_ID")
    suspend fun countPoints(): Int

    @Query(
        "DELETE FROM tbl_tracking_session_points " +
            "WHERE sessionId = $TRACKING_SESSION_ID AND sequence >= :fromSequence"
    )
    suspend fun deletePointsFrom(fromSequence: Int)

    @Query("DELETE FROM tbl_tracking_session WHERE id = $TRACKING_SESSION_ID")
    suspend fun deleteSession()
}

private fun TrackingSessionPointEntity.isAt(coordinates: Coordinates): Boolean =
    latitude == coordinates.latitude && longitude == coordinates.longitude
