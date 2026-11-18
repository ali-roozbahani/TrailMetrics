package dev.roozbahani.trailmetrics

import android.content.pm.ApplicationInfo
import android.os.StrictMode

/**
 * Installs the StrictMode policies of a debug build (`tm-robustness` M8): a thread policy that reports blocking
 * calls on the main thread (`C1`) and a VM policy that reports leaked closables, activities and SQLite objects.
 * The penalty is a log line, never a crash: a crash penalty would make the instrumented tests flaky on CI emulators.
 * A build that is not debuggable (release) gets no policy at all.
 */
internal fun installDebugStrictMode(applicationInfo: ApplicationInfo) {
    if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
    StrictMode.setThreadPolicy(debugThreadPolicy())
    StrictMode.setVmPolicy(debugVmPolicy())
}

internal fun debugThreadPolicy(): StrictMode.ThreadPolicy =
    StrictMode.ThreadPolicy.Builder()
        .detectAll()
        .penaltyLog()
        .build()

internal fun debugVmPolicy(): StrictMode.VmPolicy =
    StrictMode.VmPolicy.Builder()
        .detectLeakedClosableObjects()
        .detectActivityLeaks()
        .detectLeakedSqlLiteObjects()
        .penaltyLog()
        .build()
