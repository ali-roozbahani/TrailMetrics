package dev.roozbahani.trailmetrics.data.local.repository

import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.mapper.toDomain
import dev.roozbahani.trailmetrics.data.local.mapper.toEntity
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class ActivityHistoryRepositoryImpl(
    private val activityDao: ActivityDao,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ActivityHistoryRepository {
    override suspend fun saveActivity(activity: ActivityRecord): Long =
        withContext(ioDispatcher) {
            activityDao.insert(activity.toEntity())
        }

    override fun observeActivities(): Flow<List<ActivityRecord>> =
        activityDao.observeAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun getActivity(id: Long): ActivityRecord? =
        withContext(ioDispatcher) {
            activityDao.getById(id)?.toDomain()
        }

    override suspend fun deleteActivity(id: Long) =
        withContext(ioDispatcher) {
            activityDao.delete(id)
        }
}
