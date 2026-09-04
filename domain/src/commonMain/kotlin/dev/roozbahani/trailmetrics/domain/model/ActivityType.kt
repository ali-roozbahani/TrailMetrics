package dev.roozbahani.trailmetrics.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class ActivityType {
    Running, Cycling, Walking
}
