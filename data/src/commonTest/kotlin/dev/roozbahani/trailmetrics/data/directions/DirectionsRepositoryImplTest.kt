package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
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

    // Mirrors DirectionsResponseDto and the Json configuration of networkModule's HttpClient.
    private fun repositoryRespondingWith(polyline: String, legDistances: List<Int> = listOf(1000)): DirectionsRepositoryImpl {
        val legs = legDistances.joinToString(",") { """{"distance":{"text":"$it m","value":$it}}""" }
        val body = """
            {
              "status": "OK",
              "routes": [
                {
                  "overview_polyline": { "points": "$polyline" },
                  "legs": [$legs]
                }
              ]
            }
        """.trimIndent()
        val engine = MockEngine {
            respond(
                content = body,
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json"),
            )
        }
        val client = HttpClient(engine) {
            install(ContentNegotiation) {
                json(
                    Json {
                        ignoreUnknownKeys = true
                        isLenient = true
                    }
                )
            }
        }
        return DirectionsRepositoryImpl(httpClient = client, apiKey = "test-key")
    }
}
