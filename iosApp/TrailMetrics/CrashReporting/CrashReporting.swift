import FirebaseCore
import FirebaseCrashlytics
import Foundation
import SharedKit

/// Crash reporting with Firebase Crashlytics: the only place in the app that names a Firebase type.
///
/// It starts only when the owner's `GoogleService-Info.plist` (git-ignored, dropped into `iosApp/TrailMetrics/`)
/// is in the app bundle; without it nothing is configured and nothing is reported, which is how the gate, CI
/// and a fresh clone build. Crashlytics then reports signals and Objective-C exceptions itself; an uncaught
/// Kotlin exception reaches it through the Kotlin hook (`installFatalKotlinExceptionReporter`), which records the
/// Kotlin stack before the process ends.
enum CrashReporting {
    static func startIfConfigured(bundle: Bundle = .main) {
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
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
        crashlytics.record(exceptionModel: model)
    }
}
