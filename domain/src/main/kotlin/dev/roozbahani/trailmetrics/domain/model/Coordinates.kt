package dev.roozbahani.trailmetrics.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class Coordinates(val latitude: Double, val longitude: Double)
