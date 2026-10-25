package dev.roozbahani.trailmetrics.core.testing

import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher

class FakeTrackingServiceLauncher : TrackingServiceLauncher {
    var startCalls: Int = 0
        private set
    var stopCalls: Int = 0
        private set

    /** When set, [stop] throws it (after counting the call). */
    var stopFailure: Exception? = null

    override fun start() {
        startCalls++
    }

    override fun stop() {
        stopCalls++
        stopFailure?.let { throw it }
    }
}
