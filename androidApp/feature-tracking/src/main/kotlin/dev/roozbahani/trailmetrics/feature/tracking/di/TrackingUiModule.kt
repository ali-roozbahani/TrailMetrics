package dev.roozbahani.trailmetrics.feature.tracking.di

import dev.roozbahani.trailmetrics.feature.tracking.TrackingViewModel
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val trackingUiModule = module {
    // CalorieCalculator is registered in commonMain's useCaseModule (data/di/UseCaseModule.kt)
    // so both platforms share one registration.
    viewModel { params ->
        TrackingViewModel(
            trackingSessionManager = get(),
            userProfileRepository = get(),
            calorieCalculator = get(),
            saveActivityUseCase = get(),
            activityType = params.get(),
            plannedRoutePoints = params.get(),
            clock = get()
        )
    }
}
