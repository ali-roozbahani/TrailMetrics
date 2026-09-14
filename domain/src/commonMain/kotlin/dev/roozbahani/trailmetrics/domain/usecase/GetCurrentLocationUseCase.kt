package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlin.coroutines.cancellation.CancellationException

class GetCurrentLocationUseCase(
    private val locationRepository: LocationRepository
) {
    @Throws(RouteError::class, CancellationException::class)
    suspend operator fun invoke(): Coordinates {
        return locationRepository.getCurrentLocation().getOrThrow()
    }
}
