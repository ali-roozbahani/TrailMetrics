package dev.roozbahani.trailmetrics.data.common

import android.os.SystemClock as AndroidSystemClock

// elapsedRealtime() includes time spent in deep sleep; uptimeMillis() would not.
internal actual fun platformElapsedRealtimeMillis(): Long = AndroidSystemClock.elapsedRealtime()
