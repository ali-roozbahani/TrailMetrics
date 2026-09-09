package dev.roozbahani.trailmetrics.feature.route.di

import dev.roozbahani.trailmetrics.feature.route.RouteViewModel
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val routeModule = module {
    viewModel {
        RouteViewModel(
            getCurrentLocationUseCase = get(),
            generateClosedRouteUseCase = get(),
            userProfileRepository = get()
        )
    }
}
