package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.coroutines.flow.Flow

interface LocationRepository {
    suspend fun getCurrentLocation(): Result<Coordinates>
    fun observeLocationUpdates(): Flow<Coordinates>
}
