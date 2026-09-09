package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

class KoinHelper : KoinComponent {
    private val activityHistoryRepository: ActivityHistoryRepository by inject()

    fun getActivityHistoryRepository(): ActivityHistoryRepository = activityHistoryRepository
}
