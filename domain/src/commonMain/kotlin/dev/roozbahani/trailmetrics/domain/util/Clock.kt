package dev.roozbahani.trailmetrics.domain.util

interface Clock {
    /**
     * Wall-clock time as epoch milliseconds. Can jump backwards or forwards when the system
     * time changes (NTP correction, the user setting the time), so use it only for timestamps
     * that are stored or shown, never to measure a duration.
     */
    fun nowMillis(): Long

    /**
     * Monotonic milliseconds for measuring durations. Unaffected by wall-clock changes and
     * keeps counting while the device is asleep. The origin is arbitrary, so a single read
     * means nothing: only the difference between two reads is meaningful.
     */
    fun elapsedRealtimeMillis(): Long
}
