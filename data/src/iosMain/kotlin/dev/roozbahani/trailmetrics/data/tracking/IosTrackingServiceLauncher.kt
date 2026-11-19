package dev.roozbahani.trailmetrics.data.tracking

import dev.roozbahani.trailmetrics.domain.tracking.BackgroundLocationUpdates
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher

class IosTrackingServiceLauncher(
    private val backgroundLocationUpdates: BackgroundLocationUpdates
) : TrackingServiceLauncher {
    override fun start() {
        backgroundLocationUpdates.setEnabled(true)
    }

    override fun stop() {
        backgroundLocationUpdates.setEnabled(false)
    }
}
