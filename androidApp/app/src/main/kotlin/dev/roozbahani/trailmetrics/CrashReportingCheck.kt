package dev.roozbahani.trailmetrics

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * The deliberate crash and ANR of a debug build, to check by hand that crash reporting delivers them (the owner's
 * check with a device and the Firebase console; nothing else can show it):
 *
 * ```
 * adb shell am broadcast -a dev.roozbahani.trailmetrics.CRASH_REPORTING_CHECK --es kind crash
 * adb shell am broadcast --receiver-foreground -a dev.roozbahani.trailmetrics.CRASH_REPORTING_CHECK --es kind anr
 * ```
 *
 * The receiver is registered at runtime, exported (the shell sends the broadcast), and only when the build is
 * debuggable, like the StrictMode policies (`installDebugStrictMode`): a release build registers nothing, so no
 * other app can reach it there.
 */
internal fun installCrashReportingCheck(context: Context) {
    if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
    ContextCompat.registerReceiver(
        context,
        CrashReportingCheckReceiver(),
        IntentFilter(CrashReportingCheckReceiver.ACTION),
        ContextCompat.RECEIVER_EXPORTED,
    )
}

/**
 * `crash` throws [CrashReportingCheckException] from `onReceive`, on the main thread, so it is uncaught;
 * `anr` blocks the main thread for [ANR_BLOCK_MILLIS], longer than the 10 s limit of a foreground broadcast,
 * which the system reports as an ANR. Both are the point of the check (`tm-robustness` C1 and C5 on purpose).
 */
internal class CrashReportingCheckReceiver(
    private val blockMainThread: (Long) -> Unit = Thread::sleep,
) : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (val kind = intent.getStringExtra(EXTRA_KIND)) {
            KIND_CRASH -> throw CrashReportingCheckException()
            KIND_ANR -> blockMainThread(ANR_BLOCK_MILLIS)
            else -> Log.w(TAG, "Unknown kind '$kind': expected '$KIND_CRASH' or '$KIND_ANR'")
        }
    }

    companion object {
        const val ACTION = "dev.roozbahani.trailmetrics.CRASH_REPORTING_CHECK"
        const val EXTRA_KIND = "kind"
        const val KIND_CRASH = "crash"
        const val KIND_ANR = "anr"
        const val ANR_BLOCK_MILLIS = 30_000L
        private const val TAG = "CrashReportingCheck"
    }
}

/** The uncaught exception of the debug crash check; its name says in the crash report that it was deliberate. */
internal class CrashReportingCheckException :
    IllegalStateException("Deliberate crash of the crash reporting check (debug build)")
