package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.engine.HttpClientEngineFactory
import io.ktor.client.engine.darwin.Darwin

actual val httpClientEngine: HttpClientEngineFactory<*> = Darwin

actual fun platformDefaultHeaders(): Map<String, String> =
    emptyMap() // Google verifies iOS through a Bundle ID not headers then we return en empty map
