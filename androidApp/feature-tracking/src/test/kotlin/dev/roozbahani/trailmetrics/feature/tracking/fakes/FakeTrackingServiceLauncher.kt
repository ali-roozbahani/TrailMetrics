package dev.roozbahani.trailmetrics.feature.tracking.fakes

import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher

class FakeTrackingServiceLauncher : TrackingServiceLauncher {
    var startCalls: Int = 0
        private set
    var stopCalls: Int = 0
        private set

    override fun start() {
        startCalls++
    }

    override fun stop() {
        stopCalls++
    }
}
