//
//  StopTrackingIntent.swift
//  TrackingWidgetExtension
//

import AppIntents
import Foundation

struct StopTrackingIntent: LiveActivityIntent {
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
