package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.tracking.AndroidTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.koin.core.qualifier.named
import org.koin.dsl.module

private val TRACKING_SCOPE = named("trackingScope")

val trackingModule = module {
    single<CoroutineScope>(TRACKING_SCOPE) {
        CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }

    single<TrackingServiceLauncher> { AndroidTrackingServiceLauncher(get()) }

    single {
        TrackingSessionManager(
            locationRepository = get(),
            updateTrackingStateUseCase = get(),
            trackingServiceLauncher = get(),
            clock = get(),
            logger = get(),
            scope = get(TRACKING_SCOPE)
        )
    }
}
