package dev.roozbahani.trailmetrics.data.tracking

import dev.roozbahani.trailmetrics.data.location.IosLocationRepositoryImpl
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher

class IosTrackingServiceLauncher(
    private val locationRepository: IosLocationRepositoryImpl
) : TrackingServiceLauncher {
    override fun start() {
        locationRepository.setBackgroundUpdatesEnabled(true)
    }

    override fun stop() {
        locationRepository.setBackgroundUpdatesEnabled(false)
    }
}
