package dev.roozbahani.trailmetrics.data.common

import kotlinx.coroutines.CancellationException

interface GoogleApiResponse {
    val status: String
}

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
