package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository

class GetCurrentLocationUseCase(
    private val locationRepository: LocationRepository
) {
    suspend operator fun invoke(): Result<Coordinates> {
        return locationRepository.getCurrentLocation()
    }
}