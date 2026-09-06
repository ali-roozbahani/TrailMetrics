package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.location.IosLocationRepositoryImpl
import dev.roozbahani.trailmetrics.data.tracking.IosTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import org.koin.dsl.bind
import org.koin.dsl.module

val iosLocationModule = module {
    single { IosLocationRepositoryImpl() } bind LocationRepository::class
    single<TrackingServiceLauncher> {
        IosTrackingServiceLauncher(get<IosLocationRepositoryImpl>())
    }
}
