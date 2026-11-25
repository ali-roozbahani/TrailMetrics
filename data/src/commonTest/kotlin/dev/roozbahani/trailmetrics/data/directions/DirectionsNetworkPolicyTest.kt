package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.data.common.HttpStatusException
import dev.roozbahani.trailmetrics.data.common.NetworkTimeouts
import dev.roozbahani.trailmetrics.data.common.mockHttpClient
import dev.roozbahani.trailmetrics.data.common.respondJson
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.network.sockets.ConnectTimeoutException
import io.ktor.client.plugins.HttpTimeoutCapability
import io.ktor.client.plugins.HttpTimeoutConfig
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import kotlinx.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * The Directions call's timeouts and retries (owner decision of 2026-11-25), on the real repository and the
 * app's client configuration over Ktor's MockEngine: at most two retries, only after a timeout, a connection
 * failure or an HTTP 5xx, and a call that got no response at all ends as [RouteError.NoConnection].
 */
class DirectionsNetworkPolicyTest {

    private val start = Coordinates(latitude = 38.5, longitude = -120.2)
    private val waypoints = listOf(Coordinates(latitude = 40.7, longitude = -120.95))
    private val okBody = DirectionsResponseFixtures.response(
        routes = listOf(DirectionsResponseFixtures.route(PolylineFixtures.REFERENCE))
    )

    private var requests = 0
    private val retryDelays = mutableListOf<Long>()

    @Test
    fun `every attempt carries the decided connect, socket and request timeouts`() = runTest {
        var timeouts: HttpTimeoutConfig? = null
        val repository = repository { request ->
            timeouts = request.getCapabilityOrNull(HttpTimeoutCapability)
            respondJson(okBody)
        }

        repository.getClosedRoute(start, waypoints)

        assertEquals(10_000L, timeouts?.connectTimeoutMillis)
        assertEquals(15_000L, timeouts?.socketTimeoutMillis)
        assertEquals(30_000L, timeouts?.requestTimeoutMillis)
    }

    @Test
    fun `a server error is retried twice with a short backoff and then returns DirectionsApiError`() = runTest {
        val repository = repository { respondJson("{}", status = HttpStatusCode.ServiceUnavailable) }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertEquals(3, requests)
        assertEquals(503, assertIs<HttpStatusException>(assertIs<RouteError.DirectionsApiError>(error).apiException).statusCode)
        assertEquals(2, retryDelays.size)
        assertTrue(retryDelays[0] in 500L..750L, "first backoff ${retryDelays[0]} ms")
        assertTrue(retryDelays[1] in 1_000L..1_250L, "second backoff ${retryDelays[1]} ms")
    }

    @Test
    fun `a server error followed by a success returns the route`() = runTest {
        val repository = repository {
            if (requests == 1) respondJson("{}", status = HttpStatusCode.BadGateway) else respondJson(okBody)
        }

        val result = repository.getClosedRoute(start, waypoints)

        assertTrue(result.isSuccess)
        assertEquals(2, requests)
    }

    @Test
    fun `a client error is not retried`() = runTest {
        val repository = repository { respondJson("{}", status = HttpStatusCode.Forbidden) }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertIs<RouteError.DirectionsApiError>(error)
        assertEquals(1, requests)
    }

    @Test
    fun `an API status error is not retried`() = runTest {
        val repository = repository { respondJson(DirectionsResponseFixtures.response(status = "REQUEST_DENIED", routes = emptyList())) }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertIs<RouteError.DirectionsApiError>(error)
        assertEquals(1, requests)
    }

    @Test
    fun `a body the app cannot read is not retried`() = runTest {
        val repository = repository { respondJson("""{"status":"OK","routes":[{"overview_polyline":""") }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertIs<RouteError.DirectionsApiError>(error)
        assertEquals(1, requests)
    }

    @Test
    fun `a connection failure is retried twice and then returns NoConnection`() = runTest {
        val repository = repository { throw IOException("unreachable") }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertIs<IOException>(assertIs<RouteError.NoConnection>(error).networkException)
        assertEquals(3, requests)
        assertEquals(2, retryDelays.size)
    }

    @Test
    fun `a connection failure followed by a success returns the route`() = runTest {
        val repository = repository { if (requests == 1) throw IOException("unreachable") else respondJson(okBody) }

        val result = repository.getClosedRoute(start, waypoints)

        assertTrue(result.isSuccess)
        assertEquals(2, requests)
    }

    @Test
    fun `a connect timeout is retried twice and then returns NoConnection`() = runTest {
        val repository = repository { throw ConnectTimeoutException("connect timeout") }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertIs<RouteError.NoConnection>(error)
        assertEquals(3, requests)
    }

    @Test
    fun `a request that outlasts the request timeout is retried twice and then returns NoConnection`() = runTest {
        // A short request timeout so that the test does not wait 30 s; the handler outlasts it on the engine's
        // own (real-time) dispatcher, and the timeout cancels it.
        val repository = repository(NetworkTimeouts(requestMillis = 50L)) {
            delay(10_000L)
            respondJson(okBody)
        }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertIs<RouteError.NoConnection>(error)
        assertEquals(3, requests)
    }

    @Test
    fun `a cancellation is not retried and is rethrown`() = runTest {
        val repository = repository { throw CancellationException("cancelled") }

        assertFailsWith<CancellationException> { repository.getClosedRoute(start, waypoints) }
        assertEquals(1, requests)
    }

    @Test
    fun `an engine failure that is not a network failure is not retried`() = runTest {
        val repository = repository { throw IllegalStateException("engine bug") }

        val error = repository.getClosedRoute(start, waypoints).exceptionOrNull()

        assertIs<RouteError.DirectionsApiError>(error)
        assertEquals(1, requests)
    }

    private fun repository(timeouts: NetworkTimeouts = NetworkTimeouts(), handler: MockRequestHandler) =
        RealTimeDirectionsRepository(
            DirectionsRepositoryImpl(
                httpClient = mockHttpClient(timeouts, retryDelays) { request ->
                    requests++
                    handler(request)
                },
                apiKey = "test-key"
            )
        )
}
