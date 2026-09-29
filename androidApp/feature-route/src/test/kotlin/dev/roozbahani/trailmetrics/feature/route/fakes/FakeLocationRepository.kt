package dev.roozbahani.trailmetrics.feature.route.fakes

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

class FakeLocationRepository(
    var currentLocationResult: Result<Coordinates>
) : LocationRepository {
    var getCurrentLocationCalls: Int = 0
        private set

    override suspend fun getCurrentLocation(): Result<Coordinates> {
        getCurrentLocationCalls++
        return currentLocationResult
    }

    override fun observeLocationUpdates(): Flow<LocationUpdate> = emptyFlow()
}
