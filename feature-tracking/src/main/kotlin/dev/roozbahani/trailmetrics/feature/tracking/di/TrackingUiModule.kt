package dev.roozbahani.trailmetrics.feature.tracking.di

import dev.roozbahani.trailmetrics.core.error.RouteUiErrorMapper
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.feature.tracking.TrackingViewModel
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val trackingUiModule = module {
    factory { RouteUiErrorMapper() }
    factory { CalorieCalculator() }
    viewModel { params ->
        TrackingViewModel(
            trackingSessionManager = get(),
            userProfileRepository = get(),
            calorieCalculator = get(),
            activityType = params.get(),
            uiErrorMapper = get()
        )
    }
}
