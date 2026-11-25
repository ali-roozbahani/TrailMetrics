package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.HttpClientConfig
import io.ktor.client.plugins.HttpResponseValidator
import io.ktor.http.isSuccess

// Fails every call through the client on a non-2xx response, before the body is read.
fun HttpClientConfig<*>.failOnNonSuccessStatus() {
    HttpResponseValidator {
        validateResponse { response ->
            if (!response.status.isSuccess()) {
                throw HttpStatusException(response.status.value, response.status.description)
            }
        }
    }
}
