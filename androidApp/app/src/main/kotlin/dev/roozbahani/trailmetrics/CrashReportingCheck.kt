package dev.roozbahani.trailmetrics

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * The deliberate crash of a debug build, to check by hand that crash reporting delivers it (the owner's check with
 * a device and the Firebase console; nothing else can show it):
 *
 * ```
 * adb shell am broadcast -a dev.roozbahani.trailmetrics.CRASH_REPORTING_CHECK --es kind crash
 * ```
 *
 * A debug build reports only when built with `-Ptrailmetrics.crashReportingInDebug=true`
 * (androidApp/app/build.gradle.kts); otherwise the crash happens and nothing is sent.
 *
 * The receiver is registered at runtime and only when the build is debuggable, like the StrictMode policies
 * (`installDebugStrictMode`): a release build registers nothing. It is exported, because the shell sends the
 * broadcast, and the sender must hold [CrashReportingCheckReceiver.SENDER_PERMISSION] (`DUMP`), which the shell
 * has and a third-party app cannot be granted, so no other app on the device can trigger it (`tm-robustness` S1).
 */
internal fun installCrashReportingCheck(context: Context) {
    if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
    ContextCompat.registerReceiver(
        context,
        CrashReportingCheckReceiver(),
        IntentFilter(CrashReportingCheckReceiver.ACTION),
        CrashReportingCheckReceiver.SENDER_PERMISSION,
        null,
        ContextCompat.RECEIVER_EXPORTED,
    )
}

/** `crash` throws [CrashReportingCheckException] from `onReceive`, on the main thread, so it is uncaught. */
internal class CrashReportingCheckReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (val kind = intent.getStringExtra(EXTRA_KIND)) {
            KIND_CRASH -> throw CrashReportingCheckException()
            else -> Log.w(TAG, "Unknown kind '$kind': expected '$KIND_CRASH'")
        }
    }

    companion object {
        const val ACTION = "dev.roozbahani.trailmetrics.CRASH_REPORTING_CHECK"
        const val EXTRA_KIND = "kind"
        const val KIND_CRASH = "crash"

        /** The permission a sender of the check broadcast must hold: the shell has it, third-party apps cannot. */
        const val SENDER_PERMISSION = Manifest.permission.DUMP
        private const val TAG = "CrashReportingCheck"
    }
}

/** The uncaught exception of the debug crash check; its name says in the crash report that it was deliberate. */
internal class CrashReportingCheckException :
    IllegalStateException("Deliberate crash of the crash reporting check (debug build)")
