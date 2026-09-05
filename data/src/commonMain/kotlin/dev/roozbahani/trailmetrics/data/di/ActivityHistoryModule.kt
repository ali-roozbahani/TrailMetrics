package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.repository.ActivityHistoryRepositoryImpl
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import org.koin.dsl.module

val activityHistoryModule = module {
    single<ActivityHistoryRepository> {
        ActivityHistoryRepositoryImpl(
            activityDao = get<ActivityDao>()
        )
    }
}
