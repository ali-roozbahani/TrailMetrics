package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.BuildConfig
import dev.roozbahani.trailmetrics.data.directions.DirectionsRepositoryImpl
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import org.koin.dsl.module

val directionsModule = module {
    single<DirectionsRepository> {
        DirectionsRepositoryImpl(
            httpClient = get(),
            apiKey = BuildConfig.DIRECTIONS_API_KEY
        )
    }
}
