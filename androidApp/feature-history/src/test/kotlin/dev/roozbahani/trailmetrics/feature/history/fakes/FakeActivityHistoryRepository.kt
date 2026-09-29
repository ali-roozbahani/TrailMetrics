package dev.roozbahani.trailmetrics.feature.history.fakes

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * In-memory [ActivityHistoryRepository]. [observeActivities] emits nothing until the first
 * [setActivities] call, so a test can observe the "still loading" state.
 */
class FakeActivityHistoryRepository : ActivityHistoryRepository {
    private val activities = MutableSharedFlow<List<ActivityRecord>>(replay = 1)

    private val currentActivities: List<ActivityRecord>
        get() = activities.replayCache.lastOrNull().orEmpty()

    /** When set, [getActivity] suspends until it is completed. */
    var getActivityGate: CompletableDeferred<Unit>? = null

    /** When set, [deleteActivity] suspends until it is completed, before anything is deleted. */
    var deleteActivityGate: CompletableDeferred<Unit>? = null

    val requestedIds = mutableListOf<Long>()
    val deletedIds = mutableListOf<Long>()

    fun setActivities(records: List<ActivityRecord>) {
        activities.tryEmit(records)
    }

    override suspend fun saveActivity(activity: ActivityRecord): Long {
        setActivities(currentActivities + activity)
        return activity.id
    }

    override fun observeActivities(): Flow<List<ActivityRecord>> = activities

    override suspend fun getActivity(id: Long): ActivityRecord? {
        requestedIds += id
        getActivityGate?.await()
        return currentActivities.firstOrNull { it.id == id }
    }

    override suspend fun deleteActivity(id: Long) {
        deleteActivityGate?.await()
        deletedIds += id
        setActivities(currentActivities.filterNot { it.id == id })
    }
}
