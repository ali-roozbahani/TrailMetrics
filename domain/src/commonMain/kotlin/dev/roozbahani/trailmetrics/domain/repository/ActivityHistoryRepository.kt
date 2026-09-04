package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import kotlinx.coroutines.flow.Flow

interface ActivityHistoryRepository {
    suspend fun saveActivity(activity: ActivityRecord): Long
    fun observeActivities(): Flow<List<ActivityRecord>>
    suspend fun getActivity(id: Long): ActivityRecord?
    suspend fun deleteActivity(id: Long)
}
