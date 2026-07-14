package dev.roozbahani.trailmetrics.feature.route.di

import dev.roozbahani.trailmetrics.feature.route.RouteUiErrorMapper
import dev.roozbahani.trailmetrics.feature.route.RouteViewModel
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val routeModule = module {
    factory { RouteUiErrorMapper() }
    viewModel {
        RouteViewModel(
            getCurrentLocationUseCase = get(),
            generateClosedRouteUseCase = get(),
            uiErrorMapper = get()
        )
    }
}
