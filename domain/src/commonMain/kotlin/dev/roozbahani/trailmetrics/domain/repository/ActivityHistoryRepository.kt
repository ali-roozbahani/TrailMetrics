package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import kotlinx.coroutines.flow.Flow
import kotlin.coroutines.cancellation.CancellationException

interface ActivityHistoryRepository {
    @Throws(Exception::class, CancellationException::class)
    suspend fun saveActivity(activity: ActivityRecord): Long

    fun observeActivities(): Flow<List<ActivityRecord>>

    @Throws(Exception::class, CancellationException::class)
    suspend fun getActivity(id: Long): ActivityRecord?

    @Throws(Exception::class, CancellationException::class)
    suspend fun deleteActivity(id: Long)
}
