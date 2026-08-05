package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock
import org.koin.dsl.module

val useCaseModule = module {
    factory { GenerateClosedRouteUseCase(get()) }
    factory { GetCurrentLocationUseCase(get()) }
    factory { UpdateTrackingStateUseCase() }
    factory {
        SaveActivityUseCase(
            activityHistoryRepository = get<ActivityHistoryRepository>(),
            calorieCalculator = get<CalorieCalculator>(),
            clock = get<Clock>()
        )
    }
}
