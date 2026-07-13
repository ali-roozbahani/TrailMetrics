package dev.roozbahani.trailmetrics.data.directions

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DirectionsResponseDto(
    val status: String,
    val routes: List<RouteDto> = emptyList()
)

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
