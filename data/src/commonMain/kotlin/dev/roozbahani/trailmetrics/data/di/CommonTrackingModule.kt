package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.koin.core.qualifier.named
import org.koin.dsl.module

private val TRACKING_SCOPE = named("trackingScope")

val commonTrackingModule = module {
    single<CoroutineScope>(TRACKING_SCOPE) {
        CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }

    factory { SpeedCalculator() }

    single {
        TrackingSessionManager(
            locationRepository = get<LocationRepository>(),
            updateTrackingStateUseCase = get<UpdateTrackingStateUseCase>(),
            trackingServiceLauncher = get<TrackingServiceLauncher>(),
            speedCalculator = get<SpeedCalculator>(),
            clock = get<Clock>(),
            logger = get<Logger>(),
            scope = get<CoroutineScope>(TRACKING_SCOPE)
        )
    }
}
