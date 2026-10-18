package dev.roozbahani.trailmetrics.data.common

import kotlinx.coroutines.CancellationException

// Rethrows CancellationException and wraps any other Exception in Result.failure, so callers get a
// Result instead of a thrown exception.
@Suppress("TooGenericExceptionCaught")
suspend inline fun <R : GoogleApiResponse> safeApiCall(
    crossinline apiCall: suspend () -> R
): Result<R> =
    try {
        val response = apiCall()
        if (response.status != "OK") {
            Result.failure(IllegalArgumentException("API returned status: ${response.status}"))
        } else {
            Result.success(response)
        }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Result.failure(e)
    }

interface GoogleApiResponse {
    val status: String
}
