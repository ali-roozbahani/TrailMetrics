package dev.roozbahani.trailmetrics.data.common

import io.ktor.client.network.sockets.ConnectTimeoutException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertSame
import kotlin.test.assertTrue

class SafeApiCallTest {

    private data class FakeResponse(override val status: String) : GoogleApiResponse

    @Test
    fun `OK status returns success with the same response instance`() = runTest {
        val response = FakeResponse("OK")

        val result = safeApiCall { response }

        assertSame(response, result.getOrThrow())
    }

    @Test
    fun `non-OK status returns failure naming the status`() = runTest {
        val result = safeApiCall { FakeResponse("OVER_QUERY_LIMIT") }

        val error = assertIs<IllegalArgumentException>(result.exceptionOrNull())
        assertEquals("API returned status: OVER_QUERY_LIMIT", error.message)
    }

    @Test
    fun `thrown exception is returned as the failure`() = runTest {
        val thrown = IllegalStateException("boom")

        val result = safeApiCall<FakeResponse> { throw thrown }

        assertSame(thrown, result.exceptionOrNull())
    }

    @Test
    fun `thrown CancellationException is rethrown and not wrapped`() = runTest {
        val cancellation = CancellationException("cancelled")

        val rethrown = assertFailsWith<CancellationException> {
            safeApiCall<FakeResponse> { throw cancellation }
        }

        assertSame(cancellation, rethrown)
    }

    @Test
    fun `a cancellation that wraps a timeout while the caller is active is returned as the failure`() = runTest {
        val timeout = ConnectTimeoutException("connect timeout")

        val result = safeApiCall<FakeResponse> { throw CancellationException("timed out", timeout) }

        assertTrue(assertIs<CancellationException>(result.exceptionOrNull()).isTransportFailure())
    }

    @Test
    fun `a cancellation that wraps a timeout is rethrown when the caller itself is cancelled`() = runTest {
        var thrown: Throwable? = null
        val job = launch {
            try {
                cancel()
                safeApiCall<FakeResponse> { throw CancellationException("timed out", ConnectTimeoutException("t")) }
            } catch (e: CancellationException) {
                thrown = e
                throw e
            }
        }
        job.join()

        assertIs<CancellationException>(thrown)
        assertTrue(job.isCancelled)
    }

    @Test
    fun `api call is invoked once even when the status is not OK`() = runTest {
        var calls = 0

        safeApiCall {
            calls++
            FakeResponse("UNKNOWN_ERROR")
        }

        assertEquals(1, calls)
    }
}
