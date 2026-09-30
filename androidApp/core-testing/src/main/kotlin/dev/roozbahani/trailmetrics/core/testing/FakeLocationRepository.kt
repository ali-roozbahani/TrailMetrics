package dev.roozbahani.trailmetrics.core.testing

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * [getCurrentLocation] returns [currentLocationResult] and fails if it was never set.
 * [observeLocationUpdates] emits whatever is passed to [emit].
 */
class FakeLocationRepository(
    var currentLocationResult: Result<Coordinates>? = null
) : LocationRepository {
    private val updates = MutableSharedFlow<LocationUpdate>(extraBufferCapacity = UPDATE_BUFFER)

    var getCurrentLocationCalls: Int = 0
        private set

    override suspend fun getCurrentLocation(): Result<Coordinates> {
        getCurrentLocationCalls++
        return checkNotNull(currentLocationResult) { "currentLocationResult was not set" }
    }

    override fun observeLocationUpdates(): Flow<LocationUpdate> = updates

    fun emit(update: LocationUpdate) {
        check(updates.tryEmit(update)) { "location update buffer is full" }
    }

    private companion object {
        const val UPDATE_BUFFER = 64
    }
}
