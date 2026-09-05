package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.location.IosLocationRepositoryImpl
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import org.koin.dsl.module

val locationModule = module {
    single<LocationRepository> { IosLocationRepositoryImpl() }
}
