package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.common.httpClientEngine
import dev.roozbahani.trailmetrics.data.common.platformDefaultHeaders
import io.ktor.client.HttpClient
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.header
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import org.koin.dsl.module

val networkModule = module {
    single {
        HttpClient(httpClientEngine) {
            install(ContentNegotiation) {
                json(
                    Json {
                        ignoreUnknownKeys = true
                        isLenient = true
                    }
                )
            }

            defaultRequest {
                platformDefaultHeaders().forEach { (key, value) -> header(key, value) }
            }
        }
    }
}
