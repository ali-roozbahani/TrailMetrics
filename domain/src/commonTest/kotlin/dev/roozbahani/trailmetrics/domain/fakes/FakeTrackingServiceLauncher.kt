package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher

class FakeTrackingServiceLauncher : TrackingServiceLauncher {
    var startCallCount = 0
        private set
    var stopCallCount = 0
        private set

    override fun start() {
        startCallCount++
    }

    override fun stop() {
        stopCallCount++
    }
}
