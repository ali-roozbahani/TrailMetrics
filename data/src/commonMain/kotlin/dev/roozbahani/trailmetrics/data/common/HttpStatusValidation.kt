package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.HttpClientConfig
import io.ktor.client.plugins.HttpResponseValidator
import io.ktor.http.isSuccess

/**
 * A response with a non-2xx [statusCode]. The message names the status only: Ktor's own expectSuccess message
 * embeds the request URL, which carries the API key and the route's coordinates.
 */
class HttpStatusException(val statusCode: Int, description: String) :
    IllegalStateException("HTTP $statusCode $description") {
    val isServerError: Boolean
        get() = isServerError(statusCode)
}

/** An HTTP 5xx status: the one definition of a server error, which the retry policy uses too. */
internal fun isServerError(statusCode: Int): Boolean = statusCode in 500..599

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
