package dev.roozbahani.trailmetrics.feature.tracking.di

import dev.roozbahani.trailmetrics.feature.tracking.TrackingViewModel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import org.koin.core.module.dsl.viewModel
import org.koin.core.qualifier.named
import org.koin.dsl.module

/** Qualifier of the [CoroutineDispatcher] the Tracking screen saves the map snapshot on (blocking file IO). */
val snapshotDispatcherQualifier = named("snapshotDispatcher")

val trackingUiModule = module {
    // A feature module cannot see `:data`, so it defines the IO dispatcher it needs itself, once, here.
    single<CoroutineDispatcher>(snapshotDispatcherQualifier) { Dispatchers.IO }

    // TrackingMetricsUseCase is registered in commonMain's useCaseModule (data/di/UseCaseModule.kt)
    // so both platforms share one registration.
    viewModel { params ->
        TrackingViewModel(
            trackingSessionManager = get(),
            userProfileRepository = get(),
            trackingMetricsUseCase = get(),
            saveActivityUseCase = get(),
            activityType = params.get(),
            plannedRoutePoints = params.get(),
            clock = get(),
            snapshotFileDeleter = get()
        )
    }
}
