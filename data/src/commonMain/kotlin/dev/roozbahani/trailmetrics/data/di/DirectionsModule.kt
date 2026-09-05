package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.BuildKonfig
import dev.roozbahani.trailmetrics.data.directions.DirectionsRepositoryImpl
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import io.ktor.client.HttpClient
import org.koin.dsl.module

val directionsModule = module {
    single<DirectionsRepository> {
        DirectionsRepositoryImpl(
            httpClient = get<HttpClient>(),
            apiKey = BuildKonfig.DIRECTIONS_API_KEY
        )
    }
}
