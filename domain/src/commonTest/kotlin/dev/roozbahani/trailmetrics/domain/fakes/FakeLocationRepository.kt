package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

class FakeLocationRepository(
    private var updatesFlow: Flow<LocationUpdate> = flowOf()
) : LocationRepository {

    var observeCallCount = 0
        private set
    var currentLocationResult: Result<Coordinates> =
        Result.failure(IllegalStateException("FakeLocationRepository: currentLocationResult not set"))

    fun setUpdatesFlow(flow: Flow<LocationUpdate>) {
        updatesFlow = flow
    }

    override suspend fun getCurrentLocation(): Result<Coordinates> = currentLocationResult

    override fun observeLocationUpdates(): Flow<LocationUpdate> {
        observeCallCount++
        return updatesFlow
    }
}
