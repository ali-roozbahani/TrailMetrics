package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.location.IosLocationRepositoryImpl
import dev.roozbahani.trailmetrics.data.tracking.IosTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.tracking.BackgroundLocationUpdates
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import org.koin.dsl.binds
import org.koin.dsl.module

val iosLocationModule = module {
    // One instance serves both interfaces: the launcher switches the manager that the repository observes.
    single { IosLocationRepositoryImpl() } binds arrayOf(LocationRepository::class, BackgroundLocationUpdates::class)
    single<TrackingServiceLauncher> {
        IosTrackingServiceLauncher(get<BackgroundLocationUpdates>())
    }
}
