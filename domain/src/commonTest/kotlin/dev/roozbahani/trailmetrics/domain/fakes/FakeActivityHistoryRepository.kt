package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

class FakeActivityHistoryRepository : ActivityHistoryRepository {
    var nextSavedId: Long = 0L
    val savedActivities = mutableListOf<ActivityRecord>()

    override suspend fun saveActivity(activity: ActivityRecord): Long {
        savedActivities += activity
        return nextSavedId
    }

    override fun observeActivities(): Flow<List<ActivityRecord>> = flowOf(savedActivities.toList())

    override suspend fun getActivity(id: Long): ActivityRecord? = null

    override suspend fun deleteActivity(id: Long) {
        // not exercised by current tests
    }
}
