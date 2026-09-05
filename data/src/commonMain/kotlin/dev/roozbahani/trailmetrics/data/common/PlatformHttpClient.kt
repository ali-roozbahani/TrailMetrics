package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.engine.HttpClientEngineFactory

expect val httpClientEngine: HttpClientEngineFactory<*>

expect fun platformDefaultHeaders(): Map<String, String>
