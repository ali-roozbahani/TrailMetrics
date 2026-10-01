package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.data.common.mockHttpClient
import dev.roozbahani.trailmetrics.data.common.respondJson
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import io.ktor.client.engine.mock.MockRequestHandler
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue

class DirectionsRepositoryImplTest {

    private val start = Coordinates(latitude = 38.5, longitude = -120.2)
    private val waypoints = listOf(Coordinates(latitude = 40.7, longitude = -120.95))

    @Test
    fun `valid polyline is decoded into the route points`() = runTest {
        val repository = repositoryRespondingWith(polyline = PolylineFixtures.REFERENCE, legDistances = listOf(1200, 800))

        val route = repository.getClosedRoute(start, waypoints).getOrThrow()

        assertEquals(PolylineFixtures.REFERENCE_POINTS, route.points.map { it.coordinates.latitude to it.coordinates.longitude })
        assertEquals(2000.0, route.distanceMeters)
    }

    @Test
    fun `truncated polyline returns DirectionsApiError`() = runTest {
        val repository = repositoryRespondingWith(polyline = PolylineFixtures.TRUNCATED)

        val result = repository.getClosedRoute(start, waypoints)

        assertTrue(result.isFailure)
        assertIs<RouteError.DirectionsApiError>(result.exceptionOrNull())
    }

    @Test
    fun `polyline with an unterminated final chunk returns DirectionsApiError`() = runTest {
        val repository = repositoryRespondingWith(polyline = PolylineFixtures.UNTERMINATED)

        val result = repository.getClosedRoute(start, waypoints)

        assertTrue(result.isFailure)
        assertIs<RouteError.DirectionsApiError>(result.exceptionOrNull())
    }

    @Test
    fun `empty polyline currently returns a successful route with no points`() = runTest {
        val repository = repositoryRespondingWith(polyline = "", legDistances = listOf(500))

        val route = repository.getClosedRoute(start, waypoints).getOrThrow()

        assertEquals(emptyList(), route.points)
        assertEquals(500.0, route.distanceMeters)
    }

    @Test
    fun `ZERO_RESULTS status returns DirectionsApiError carrying the status`() = runTest {
        val repository = repository { respondJson("""{"status":"ZERO_RESULTS","routes":[]}""") }

        val cause = apiErrorCause(repository.getClosedRoute(start, waypoints))

        assertIs<IllegalArgumentException>(cause)
        assertEquals("API returned status: ZERO_RESULTS", cause.message)
    }

    @Test
    fun `REQUEST_DENIED status returns DirectionsApiError carrying the status`() = runTest {
        val body = """{"status":"REQUEST_DENIED","error_message":"The provided API key is invalid.","routes":[]}"""
        val repository = repository { respondJson(body) }

        val cause = apiErrorCause(repository.getClosedRoute(start, waypoints))

        assertIs<IllegalArgumentException>(cause)
        assertEquals("API returned status: REQUEST_DENIED", cause.message)
    }

    @Test
    fun `OK status with an empty routes list returns DirectionsApiError for no routes`() = runTest {
        val repository = repository { respondJson("""{"status":"OK","routes":[]}""") }

        val cause = apiErrorCause(repository.getClosedRoute(start, waypoints))

        assertIs<IllegalStateException>(cause)
        assertEquals("No routes found", cause.message)
    }

    @Test
    fun `OK status without a routes key returns DirectionsApiError for no routes`() = runTest {
        val repository = repository { respondJson("""{"status":"OK"}""") }

        val cause = apiErrorCause(repository.getClosedRoute(start, waypoints))

        assertIs<IllegalStateException>(cause)
        assertEquals("No routes found", cause.message)
    }

    @Test
    fun `only the first of several routes is used for distance and points`() = runTest {
        val body = DirectionsResponseFixtures.response(
            routes = listOf(
                DirectionsResponseFixtures.route(PolylineFixtures.REFERENCE, legDistances = listOf(1200, 800)),
                DirectionsResponseFixtures.route(PolylineFixtures.REFERENCE.take(10), legDistances = listOf(5)),
            )
        )
        val repository = repository { respondJson(body) }

        val route = repository.getClosedRoute(start, waypoints).getOrThrow()

        assertEquals(PolylineFixtures.REFERENCE_POINTS, route.points.map { it.coordinates.latitude to it.coordinates.longitude })
        assertEquals(2000.0, route.distanceMeters)
    }

    @Test
    fun `HTTP 500 with a non-JSON body returns DirectionsApiError`() = runTest {
        val repository = repository {
            respond(
                content = "<html><body>Internal Server Error</body></html>",
                status = HttpStatusCode.InternalServerError,
                headers = headersOf(HttpHeaders.ContentType, "text/html"),
            )
        }

        val result = repository.getClosedRoute(start, waypoints)

        assertIs<RouteError.DirectionsApiError>(result.exceptionOrNull())
    }

    @Test
    fun `malformed JSON body returns DirectionsApiError`() = runTest {
        val repository = repository { respondJson("""{"status":"OK","routes":[{"overview_polyline":""") }

        val result = repository.getClosedRoute(start, waypoints)

        assertIs<RouteError.DirectionsApiError>(result.exceptionOrNull())
    }

    @Test
    fun `exception thrown by the engine is returned as DirectionsApiError wrapping it`() = runTest {
        val repository = repository { throw IllegalStateException("network down") }

        val cause = apiErrorCause(repository.getClosedRoute(start, waypoints))

        // Not assertSame: on the JVM, coroutines stack-trace recovery may rethrow a copy across the
        // suspend boundary inside Ktor.
        assertIs<IllegalStateException>(cause)
        assertEquals("network down", cause.message)
    }

    @Test
    fun `CancellationException thrown by the engine is rethrown instead of returned as a failure`() = runTest {
        val repository = repository { throw CancellationException("cancelled") }

        assertFailsWith<CancellationException> { repository.getClosedRoute(start, waypoints) }
    }

    @Test
    fun `request targets the Directions endpoint`() = runTest {
        val request = captureRequest(waypoints)

        assertEquals("maps.googleapis.com", request.url.host)
        assertEquals("/maps/api/directions/json", request.url.encodedPath)
    }

    @Test
    fun `request uses the start point as both origin and destination`() = runTest {
        val request = captureRequest(waypoints)

        assertEquals("38.5,-120.2", request.url.parameters["origin"])
        assertEquals("38.5,-120.2", request.url.parameters["destination"])
    }

    @Test
    fun `request joins several waypoints with a pipe`() = runTest {
        val threeWaypoints = listOf(
            Coordinates(latitude = 40.7, longitude = -120.95),
            Coordinates(latitude = 43.252, longitude = -126.453),
            Coordinates(latitude = 39.0, longitude = -121.5),
        )

        val request = captureRequest(threeWaypoints)

        assertEquals("40.7,-120.95|43.252,-126.453|39.0,-121.5", request.url.parameters["waypoints"])
    }

    @Test
    fun `request sends the api key`() = runTest {
        val request = captureRequest(waypoints)

        assertEquals(API_KEY, request.url.parameters["key"])
    }

    @Test
    fun `HTTP error status with a valid OK body currently returns a successful route`() = runTest {
        val body = DirectionsResponseFixtures.response(
            routes = listOf(DirectionsResponseFixtures.route(PolylineFixtures.REFERENCE, legDistances = listOf(1200, 800)))
        )
        val repository = repository { respondJson(body, status = HttpStatusCode.ServiceUnavailable) }

        val route = repository.getClosedRoute(start, waypoints).getOrThrow()

        assertEquals(2000.0, route.distanceMeters)
    }

    private fun repository(handler: MockRequestHandler) =
        DirectionsRepositoryImpl(httpClient = mockHttpClient(handler), apiKey = API_KEY)

    private fun repositoryRespondingWith(polyline: String, legDistances: List<Int> = listOf(1000)): DirectionsRepositoryImpl {
        val body = DirectionsResponseFixtures.response(routes = listOf(DirectionsResponseFixtures.route(polyline, legDistances)))
        return repository { respondJson(body) }
    }

    private suspend fun captureRequest(waypoints: List<Coordinates>): HttpRequestData {
        var captured: HttpRequestData? = null
        val body = DirectionsResponseFixtures.response(routes = listOf(DirectionsResponseFixtures.route(PolylineFixtures.REFERENCE)))
        val repository = repository { request ->
            captured = request
            respondJson(body)
        }

        repository.getClosedRoute(start, waypoints).getOrThrow()

        return checkNotNull(captured) { "no request reached the engine" }
    }

    private fun apiErrorCause(result: Result<*>): Throwable =
        assertIs<RouteError.DirectionsApiError>(result.exceptionOrNull()).apiException

    private companion object {
        const val API_KEY = "test-key"
    }
}
