package dev.roozbahani.trailmetrics.feature.tracking.fakes

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

class FakeActivityHistoryRepository : ActivityHistoryRepository {
    private val activities = MutableStateFlow<List<ActivityRecord>>(emptyList())

    val savedActivities: List<ActivityRecord>
        get() = activities.value

    override suspend fun saveActivity(activity: ActivityRecord): Long {
        val id = activities.value.size + 1L
        activities.value += activity.copy(id = id)
        return id
    }

    override fun observeActivities(): Flow<List<ActivityRecord>> = activities

    override suspend fun getActivity(id: Long): ActivityRecord? = activities.value.find { it.id == id }

    override suspend fun deleteActivity(id: Long) {
        activities.value = activities.value.filterNot { it.id == id }
    }
}
