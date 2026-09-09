package dev.roozbahani.trailmetrics.feature.history.di

import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.feature.history.DetailsViewModel
import dev.roozbahani.trailmetrics.feature.history.HistoryViewModel
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val historyUiModule = module {
    viewModel {
        HistoryViewModel(
            activityHistoryRepository = get<ActivityHistoryRepository>()
        )
    }
    viewModel { params ->
        DetailsViewModel(
            activityId = params.get(),
            activityHistoryRepository = get<ActivityHistoryRepository>()
        )
    }
}
