package dev.roozbahani.trailmetrics.shared.crash

import kotlin.experimental.ExperimentalNativeApi
import kotlin.native.getStackTraceAddresses
import kotlin.native.setUnhandledExceptionHook
import kotlin.native.terminateWithUnhandledException

/**
 * The receiver of an uncaught Kotlin exception, implemented by the app's crash reporting adapter in Swift. It
 * knows no crash reporting vendor: the adapter maps [ReportedKotlinException] to its tool. [report] runs on the
 * crashing thread right before the process ends, so it must write synchronously and must not throw.
 */
interface FatalKotlinExceptionReporter {
    fun report(exception: ReportedKotlinException)
}

/**
 * An uncaught Kotlin exception as a crash report needs it: [name] is the class's qualified name, [reason] the
 * message followed by one `Caused by:` line per cause, and [stackAddresses] the return addresses of the
 * exception's own stack, top first, which the tool symbolicates with the app's dSYM.
 */
class ReportedKotlinException(
    val name: String,
    val reason: String,
    val stackAddresses: List<Long>,
)

/**
 * Installs the Kotlin/Native unhandled-exception hook: an exception that reaches the edge of Kotlin uncaught (a
 * Swift call into a function without `@Throws`, a worker, a coroutine with no handler) goes to [reporter] and then
 * terminates the process as before ([terminateWithUnhandledException]), so the crash itself is still a crash.
 * Without this the report is an abort in the Kotlin runtime with no Kotlin frame of the throw site.
 *
 * Called once, by the Swift adapter's `CrashReporting.startIfConfigured()` from `TrailMetricsApp.init`, and only
 * when crash reporting is configured.
 */
@OptIn(ExperimentalNativeApi::class) // the hook API is experimental; no stable alternative exists
fun installFatalKotlinExceptionReporter(reporter: FatalKotlinExceptionReporter) {
    setUnhandledExceptionHook { throwable ->
        reporter.report(throwable.toReportedKotlinException())
        terminateWithUnhandledException(throwable)
    }
}

@OptIn(ExperimentalNativeApi::class) // getStackTraceAddresses is experimental; no stable alternative exists
internal fun Throwable.toReportedKotlinException(): ReportedKotlinException = ReportedKotlinException(
    name = this::class.qualifiedName ?: UNKNOWN_CLASS_NAME,
    reason = reasonWithCauses(),
    stackAddresses = getStackTraceAddresses(),
)

private fun Throwable.reasonWithCauses(): String = buildString {
    append(message.orEmpty())
    var cause = cause
    var depth = 0
    while (cause != null && depth < MAX_CAUSES) {
        append("\nCaused by: ")
        append(cause::class.qualifiedName ?: UNKNOWN_CLASS_NAME)
        cause.message?.let { append(": ").append(it) }
        cause = cause.cause
        depth++
    }
}

private const val UNKNOWN_CLASS_NAME = "kotlin.Throwable"

// A cause chain that loops back on itself would never end; real chains are a few levels deep.
private const val MAX_CAUSES = 10
