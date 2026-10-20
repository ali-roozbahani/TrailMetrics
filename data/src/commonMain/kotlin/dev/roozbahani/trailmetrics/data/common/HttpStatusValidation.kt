package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.HttpClientConfig
import io.ktor.client.plugins.HttpResponseValidator
import io.ktor.http.isSuccess

// Fails every call through the client on a non-2xx response, before the body is read. The message
// names the status only: Ktor's own expectSuccess message embeds the request URL, which carries
// the API key.
fun HttpClientConfig<*>.failOnNonSuccessStatus() {
    HttpResponseValidator {
        validateResponse { response ->
            if (!response.status.isSuccess()) {
                error("HTTP ${response.status.value} ${response.status.description}")
            }
        }
    }
}
