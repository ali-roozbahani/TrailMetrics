package dev.roozbahani.trailmetrics.feature.tracking.di

import dev.roozbahani.trailmetrics.core.error.RouteUiErrorMapper
import dev.roozbahani.trailmetrics.feature.tracking.TrackingViewModel
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val trackingUiModule = module {
    factory { RouteUiErrorMapper() }
    viewModel {
        TrackingViewModel(
            trackingSessionManager = get(),
            getCurrentLocationUseCase = get(),
            uiErrorMapper = get()
        )
    }
}