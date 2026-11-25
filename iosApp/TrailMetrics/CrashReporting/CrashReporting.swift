import FirebaseCore
import FirebaseCrashlytics
import Foundation
import OSLog
import SharedKit

/// Crash reporting with Firebase Crashlytics: the only place in the app that names a Firebase type.
///
/// It starts only in a Release build (a Debug build needs `debugOptInArgument`), and only when the owner's
/// `GoogleService-Info.plist` (git-ignored, dropped into `iosApp/TrailMetrics/`)
/// is in the app bundle; without it nothing is configured and nothing is reported, which is how the gate, CI
/// and a fresh clone build. Crashlytics then reports signals and Objective-C exceptions itself; an uncaught
/// Kotlin exception reaches it through the Kotlin hook (`installFatalKotlinExceptionReporter`), which records the
/// Kotlin stack before the process ends.
enum CrashReporting {
    private static let logger = Logger(subsystem: "dev.roozbahani.TrailMetrics", category: "CrashReporting")

    /// The launch argument that switches crash reporting on in a Debug or Debug-UITest build, for the owner's
    /// manual check only: set it locally in the scheme's Run arguments and never commit that scheme change.
    static let debugOptInArgument = "-crashReportingInDebug"

    static func startIfConfigured(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) {
        // Only a Release build reports: a developer's own crashes in a Debug build never reach the Firebase
        // project, even with the config file in place, unless the opt-in argument is given.
        #if DEBUG
        guard arguments.contains(debugOptInArgument) else {
            return
        }
        #endif
        // No config file: reporting is off by design (the gate, CI, a fresh clone).
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist") else {
            return
        }
        // A config file that is there but unreadable is a broken setup, not "off": say so, and stop a debug build.
        guard let options = FirebaseOptions(contentsOfFile: path) else {
            logger.error("GoogleService-Info.plist is in the app but could not be read: crash reporting is off")
            assertionFailure("GoogleService-Info.plist is in the app but could not be read")
            return
        }
        FirebaseApp.configure(options: options)
        FatalKotlinExceptionReportingKt.installFatalKotlinExceptionReporter(
            reporter: CrashlyticsFatalKotlinExceptionReporter(crashlytics: Crashlytics.crashlytics())
        )
    }
}

/// Records an uncaught Kotlin exception with its Kotlin stack through Crashlytics' public
/// `record(exceptionModel:)`: written on the calling thread, sent on the next launch, and shown as an event next
/// to the crash that follows it. Only the public API is used (NSExceptionKt's fatal path calls a private
/// Crashlytics function, so it is not used).
nonisolated final class CrashlyticsFatalKotlinExceptionReporter: NSObject, FatalKotlinExceptionReporter {
    private let crashlytics: Crashlytics

    init(crashlytics: Crashlytics) {
        self.crashlytics = crashlytics
    }

    func report(exception: ReportedKotlinException) {
        let model = ExceptionModel(name: exception.name, reason: exception.reason)
        model.stackTrace = exception.stackAddresses.map { address in
            StackFrame(address: UInt(truncatingIfNeeded: address.int64Value))
        }
        // The process aborts right after this returns, so the event must be on disk by then. In firebase-ios-sdk
        // 13.2.0, record(exceptionModel:) -> FIRCLSExceptionRecordModel -> FIRCLSExceptionRecord, which for a
        // custom exception writes the report file on the calling thread (FIRCLSUserLoggingWriteAndCheckABFiles,
        // Crashlytics/Crashlytics/Handlers/FIRCLSException.mm), not on a queue; it is sent on the next launch.
        crashlytics.record(exceptionModel: model)
    }
}
