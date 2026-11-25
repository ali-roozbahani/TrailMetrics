package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.HttpResponseData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

// Mirrors the Json configuration of networkModule's HttpClient.
val networkJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
}

// Mirrors networkModule's HttpClient: ContentNegotiation with networkJson, failOnNonSuccessStatus and
// installNetworkPolicy (the same functions networkModule calls), so a non-2xx response fails the call and
// a failed attempt is retried as in the app. Its defaultRequest platform headers are left out: the Android
// actual resolves a Context through Koin, and no repository logic depends on them. The backoff is recorded
// in [retryDelays] instead of waited; [timeouts] are the app's unless a test shortens them.
fun mockHttpClient(
    timeouts: NetworkTimeouts = NetworkTimeouts(),
    retryDelays: MutableList<Long> = mutableListOf(),
    handler: MockRequestHandler
): HttpClient =
    HttpClient(MockEngine(handler)) {
        install(ContentNegotiation) {
            json(networkJson)
        }
        failOnNonSuccessStatus()
        installNetworkPolicy(timeouts = timeouts, retryDelay = { retryDelays += it })
    }

fun MockRequestHandleScope.respondJson(body: String, status: HttpStatusCode = HttpStatusCode.OK): HttpResponseData =
    respond(
        content = body,
        status = status,
        headers = headersOf(HttpHeaders.ContentType, "application/json"),
    )
