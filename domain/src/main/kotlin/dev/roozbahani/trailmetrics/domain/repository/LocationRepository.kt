package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import kotlinx.coroutines.flow.Flow

interface LocationRepository {
    suspend fun getCurrentLocation(): Result<Coordinates>
    fun observeLocationUpdates(): Flow<LocationUpdate>
}
