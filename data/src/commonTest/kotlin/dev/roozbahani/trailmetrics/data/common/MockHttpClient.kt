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

// Mirrors networkModule's HttpClient: ContentNegotiation with networkJson and no expectSuccess, so a
// non-2xx response is not thrown by Ktor. Its defaultRequest platform headers are left out: the
// Android actual resolves a Context through Koin, and no repository logic depends on them.
fun mockHttpClient(handler: MockRequestHandler): HttpClient =
    HttpClient(MockEngine(handler)) {
        install(ContentNegotiation) {
            json(networkJson)
        }
    }

fun MockRequestHandleScope.respondJson(body: String, status: HttpStatusCode = HttpStatusCode.OK): HttpResponseData =
    respond(
        content = body,
        status = status,
        headers = headersOf(HttpHeaders.ContentType, "application/json"),
    )
