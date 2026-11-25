package dev.roozbahani.trailmetrics.data.common

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive

// Rethrows CancellationException and wraps any other Exception in Result.failure, so callers get a
// Result instead of a thrown exception. A cancellation that only wraps a timeout (Ktor can end a timed-out
// call that way) while the caller is still active is a failure of the call, not of the caller: it is returned.
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
        if (e.isTransportFailure() && currentCoroutineContext().isActive) Result.failure(e) else throw e
    } catch (e: Exception) {
        Result.failure(e)
    }

interface GoogleApiResponse {
    val status: String
}
