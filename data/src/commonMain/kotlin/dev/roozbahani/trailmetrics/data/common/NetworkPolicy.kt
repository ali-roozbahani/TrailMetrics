package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.HttpClientConfig
import io.ktor.client.network.sockets.ConnectTimeoutException
import io.ktor.client.network.sockets.SocketTimeoutException
import io.ktor.client.plugins.HttpRequestRetry
import io.ktor.client.plugins.HttpRequestTimeoutException
import io.ktor.client.plugins.HttpTimeout
import kotlinx.coroutines.CancellationException
import kotlinx.io.IOException

/**
 * The timeouts of the Directions call (owner decision of 2026-11-25). Each applies to one attempt: with
 * [MAX_RETRIES] retries a call can take up to three request timeouts plus the backoff. The Darwin engine (iOS)
 * has a single per-request interval, which Ktor sets from [socketMillis]; it has no separate connect timeout.
 */
data class NetworkTimeouts(
    val connectMillis: Long = 10_000L,
    val socketMillis: Long = 15_000L,
    val requestMillis: Long = 30_000L
)

/** Retries after the first attempt, at most (owner decision of 2026-11-25). */
const val MAX_RETRIES = 2

/** The backoff: 500 ms before the first retry, 1 s before the second, each plus up to 250 ms of jitter. */
private const val RETRY_BASE_DELAY_MILLIS = 500L
private const val RETRY_MAX_DELAY_MILLIS = 2_000L
private const val RETRY_JITTER_MILLIS = 250L

/**
 * Installs the timeouts and the retry policy: at most [MAX_RETRIES] retries with a short exponential backoff,
 * only after a timeout, a connection failure ([isTransportFailure]) or an HTTP 5xx; never after a 4xx, a
 * response the app cannot use (an API status, a body it cannot read) or a cancellation. [retryDelay] waits the
 * backoff; a test replaces it so that it does not wait.
 */
fun HttpClientConfig<*>.installNetworkPolicy(
    timeouts: NetworkTimeouts = NetworkTimeouts(),
    retryDelay: suspend (Long) -> Unit = { kotlinx.coroutines.delay(it) }
) {
    // Before HttpTimeout: Ktor passes a timeout to the retry only in this order.
    install(HttpRequestRetry) {
        maxRetries = MAX_RETRIES
        retryIf { _, response -> isServerError(response.status.value) }
        retryOnExceptionIf { _, cause -> cause.isRetryable() }
        exponentialDelay(
            baseDelayMs = RETRY_BASE_DELAY_MILLIS,
            maxDelayMs = RETRY_MAX_DELAY_MILLIS,
            randomizationMs = RETRY_JITTER_MILLIS
        )
        delay(retryDelay)
    }
    install(HttpTimeout) {
        connectTimeoutMillis = timeouts.connectMillis
        socketTimeoutMillis = timeouts.socketMillis
        requestTimeoutMillis = timeouts.requestMillis
    }
}

private fun Throwable.isRetryable(): Boolean = when (this) {
    is HttpStatusException -> isServerError
    else -> isTransportFailure()
}

/**
 * True when the call got no HTTP response: a timeout, or a connection failure (no network, a host that cannot
 * be resolved or reached, a connection lost mid-call), which every engine reports as an [IOException]. A
 * cancellation is not, unless Ktor wraps a timeout in it.
 */
fun Throwable.isTransportFailure(): Boolean = when (this) {
    // Ktor can wrap a timeout in one or more cancellations; the first cause that is not one decides.
    is CancellationException ->
        generateSequence(cause) { it.cause }.firstOrNull { it !is CancellationException }?.isTimeout() == true
    is IOException -> true
    else -> false
}

private fun Throwable.isTimeout(): Boolean =
    this is HttpRequestTimeoutException || this is ConnectTimeoutException || this is SocketTimeoutException
