package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import dev.roozbahani.trailmetrics.data.BuildConfig
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.header
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import org.koin.dsl.module

val networkModule = module {
    single {
        val context = get<Context>()

        HttpClient(OkHttp) {
            install(ContentNegotiation) {
                json(
                    Json {
                        ignoreUnknownKeys = true
                        isLenient = true
                    }
                )
            }

            defaultRequest {
                header("X-Android-Package", context.packageName)
                header("X-Android-Cert", BuildConfig.ANDROID_CERT_SHA1.replace(":", ""))
            }
        }
    }
}
