package dev.roozbahani.trailmetrics.data.local.dao

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query
import dev.roozbahani.trailmetrics.data.local.entity.ActivityEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ActivityDao {

    @Insert
    suspend fun insert(activity: ActivityEntity): Long

    @Query("SELECT * FROM tbl_activities ORDER BY startedAtEpochMillis DESC")
    fun observeAll(): Flow<List<ActivityEntity>>

    @Query("SELECT * FROM tbl_activities WHERE id = :id")
    suspend fun getById(id: Long): ActivityEntity?

    @Query("DELETE FROM tbl_activities WHERE id = :id")
    suspend fun delete(id: Long)
}
