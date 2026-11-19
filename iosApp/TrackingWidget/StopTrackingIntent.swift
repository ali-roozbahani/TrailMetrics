//
//  StopTrackingIntent.swift
//  TrackingWidgetExtension
//

import AppIntents
import Foundation

struct StopTrackingIntent: LiveActivityIntent {
    // `title` is a requirement of `AppIntent`: the system reads it, nothing in the code does (SwiftLint's analyzer
    // reports it as unused, 2026-11-19).
    static var title: LocalizedStringResource = "Stop Tracking"
    static var description = IntentDescription("Stops the current TrailMetrics tracking session.")

    // Runs in the widget extension's own process, not the main app's.
    // TrackingSessionManager is an in-memory Kotlin singleton scoped to the
    // main app process, so this intent has no direct way to reach it. This
    // posts a Darwin notification instead — a best-effort, no-payload signal
    // that only reaches the main app if its process is still alive (see
    // TrackingLiveActivityController's observer). Per this feature's confirmed scope, the
    // rare case where the app process has been fully terminated is not
    // handled here.
    // swiftlint:disable:next async_without_await - `AppIntent.perform()` is `async throws`
    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(TrackingLiveActivityConstants.stopNotificationName as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
