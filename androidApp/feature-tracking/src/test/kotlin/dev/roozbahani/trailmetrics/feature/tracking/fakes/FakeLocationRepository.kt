package dev.roozbahani.trailmetrics.feature.tracking.fakes

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

class FakeLocationRepository : LocationRepository {
    private val updates = MutableSharedFlow<LocationUpdate>(extraBufferCapacity = UPDATE_BUFFER)

    override suspend fun getCurrentLocation(): Result<Coordinates> =
        error("TrackingSessionManager only observes location updates")

    override fun observeLocationUpdates(): Flow<LocationUpdate> = updates

    fun emit(update: LocationUpdate) {
        check(updates.tryEmit(update)) { "location update buffer is full" }
    }

    private companion object {
        const val UPDATE_BUFFER = 64
    }
}
