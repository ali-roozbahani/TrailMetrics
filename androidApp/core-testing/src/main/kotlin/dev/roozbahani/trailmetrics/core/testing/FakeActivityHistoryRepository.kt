package dev.roozbahani.trailmetrics.core.testing

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.flow

/**
 * In-memory [ActivityHistoryRepository]. [observeActivities] emits nothing until the first
 * [setActivities] or [saveActivity] call, so a test can observe the "still loading" state.
 */
class FakeActivityHistoryRepository : ActivityHistoryRepository {
    private val activities = MutableSharedFlow<List<ActivityRecord>>(replay = 1)

    private val currentActivities: List<ActivityRecord>
        get() = activities.replayCache.lastOrNull().orEmpty()

    /** Every stored record, whether added by [setActivities] or [saveActivity]. */
    val savedActivities: List<ActivityRecord>
        get() = currentActivities

    /** When set, [getActivity] suspends until it is completed. */
    var getActivityGate: CompletableDeferred<Unit>? = null

    /** When set, [getActivity] throws it (after the gate) instead of returning the record. */
    var getActivityFailure: Throwable? = null

    /** When set, the flow [observeActivities] returns throws it when collected, instead of emitting. */
    var observeActivitiesFailure: Throwable? = null

    /** When set, [saveActivity] suspends until it is completed, before anything is stored. */
    var saveActivityGate: CompletableDeferred<Unit>? = null

    /** When set, [saveActivity] throws it (after the gate) instead of storing the record. */
    var saveActivityFailure: Throwable? = null

    /** When set, [deleteActivity] suspends until it is completed, before anything is deleted. */
    var deleteActivityGate: CompletableDeferred<Unit>? = null

    /** When set, [deleteActivity] throws it (after the gate) instead of deleting. */
    var deleteActivityFailure: Throwable? = null

    val requestedIds = mutableListOf<Long>()
    val deletedIds = mutableListOf<Long>()

    fun setActivities(records: List<ActivityRecord>) {
        activities.tryEmit(records)
    }

    /** Stores the record under a count-based id, like an auto-generated primary key. */
    override suspend fun saveActivity(activity: ActivityRecord): Long {
        saveActivityGate?.await()
        saveActivityFailure?.let { throw it }
        val id = currentActivities.size + 1L
        setActivities(currentActivities + activity.copy(id = id))
        return id
    }

    override fun observeActivities(): Flow<List<ActivityRecord>> =
        observeActivitiesFailure?.let { failure -> flow { throw failure } } ?: activities

    override suspend fun getActivity(id: Long): ActivityRecord? {
        requestedIds += id
        getActivityGate?.await()
        getActivityFailure?.let { throw it }
        return currentActivities.firstOrNull { it.id == id }
    }

    override suspend fun deleteActivity(id: Long) {
        deleteActivityGate?.await()
        deleteActivityFailure?.let { throw it }
        deletedIds += id
        setActivities(currentActivities.filterNot { it.id == id })
    }
}
