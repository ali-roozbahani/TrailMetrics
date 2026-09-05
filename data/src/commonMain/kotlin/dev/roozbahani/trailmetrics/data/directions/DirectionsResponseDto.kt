package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.data.common.GoogleApiResponse
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DirectionsResponseDto(
    override val status: String,
    val routes: List<RouteDto> = emptyList()
) : GoogleApiResponse

@Serializable
data class RouteDto(
    @SerialName("overview_polyline")
    val overviewPolyline: OverviewPolylineDto,
    val legs: List<LegDto>
)

@Serializable
data class OverviewPolylineDto(
    val points: String
)

@Serializable
data class LegDto(
    val distance: DistanceDto
)

@Serializable
data class DistanceDto(
    val value: Int
)
