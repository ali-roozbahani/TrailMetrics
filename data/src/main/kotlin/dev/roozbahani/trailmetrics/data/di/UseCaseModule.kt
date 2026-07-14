package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import org.koin.dsl.module

val useCaseModule = module {
    factory { GenerateClosedRouteUseCase(get()) }
    factory { GetCurrentLocationUseCase(get()) }
}
