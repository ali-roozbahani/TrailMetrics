package dev.roozbahani.trailmetrics.data.common

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
