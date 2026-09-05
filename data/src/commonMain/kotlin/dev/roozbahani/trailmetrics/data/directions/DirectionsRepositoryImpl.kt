package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.data.common.safeApiCall
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter

class DirectionsRepositoryImpl(
    private val httpClient: HttpClient,
    private val apiKey: String
) : DirectionsRepository {

    override suspend fun getClosedRoute(
        startPoint: Coordinates,
        waypoints: List<Coordinates>
    ): Result<Route> {
        val result: Result<DirectionsResponseDto> = safeApiCall {
            httpClient.get(BASE_URL) {
                parameter("origin", "${startPoint.latitude},${startPoint.longitude}")
                parameter("destination", "${startPoint.latitude},${startPoint.longitude}")
                parameter("waypoints", waypoints.joinToString("|") { "${it.latitude},${it.longitude}" })
                parameter("key", apiKey)
            }.body()
        }

        return result.fold(
            onSuccess = { response ->
                val route = response.routes.firstOrNull()
                    ?: return Result.failure(RouteError.DirectionsApiError(IllegalStateException("No routes found")))

                val totalDistanceMeters = route.legs.sumOf { it.distance.value }
                val points = decodePolyline(route.overviewPolyline.points)

                Result.success(
                    Route(
                        points = points,
                        distanceMeters = totalDistanceMeters.toDouble()
                    )
                )
            },
            onFailure = { Result.failure(RouteError.DirectionsApiError(it)) }
        )
    }

    private companion object {
        const val BASE_URL = "https://maps.googleapis.com/maps/api/directions/json"
    }
}
