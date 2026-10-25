package dev.roozbahani.trailmetrics.fakes

import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher

class FakeTrackingServiceLauncher : TrackingServiceLauncher {
    var startCalls: Int = 0
        private set
    var stopCalls: Int = 0
        private set

    /** When set, [stop] throws it, which makes the manager's `discard()` fail. */
    var stopFailure: Exception? = null

    override fun start() {
        startCalls++
    }

    override fun stop() {
        stopCalls++
        stopFailure?.let { throw it }
    }
}
