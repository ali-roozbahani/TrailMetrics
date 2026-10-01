package dev.roozbahani.trailmetrics.data.common

import kotlinx.cinterop.ExperimentalForeignApi
import platform.posix.CLOCK_MONOTONIC_RAW
import platform.posix.clock_gettime_nsec_np

private const val NANOS_PER_MILLI = 1_000_000uL

// clock_gettime(3): CLOCK_MONOTONIC_RAW ticks "like CLOCK_MONOTONIC", which "will continue to
// increment while the system is asleep", unaffected by time adjustments. CLOCK_UPTIME_RAW,
// mach_absolute_time and ProcessInfo.systemUptime stop during sleep. (mach_continuous_time also
// counts sleep but isn't exposed to Kotlin/Native's platform.darwin or platform.posix.)
@OptIn(ExperimentalForeignApi::class)
internal actual fun platformElapsedRealtimeMillis(): Long =
    (clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW.toUInt()) / NANOS_PER_MILLI).toLong()
