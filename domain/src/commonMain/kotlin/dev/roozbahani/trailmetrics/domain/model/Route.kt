package dev.roozbahani.trailmetrics.domain.model

data class Route(
    val points: List<RoutePoint>,
    val distanceMeters: Double
)
