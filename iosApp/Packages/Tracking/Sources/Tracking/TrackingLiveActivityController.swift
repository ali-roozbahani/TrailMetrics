//
//  TrackingLiveActivityController.swift
//  Tracking
//
//  Owns the Live Activity's lifecycle (request/update/end) and the Darwin
//  notification observer for its Stop button. Kept out of TrackingViewModel
//  so that class stays focused on tracking state itself.
//

import ActivityKit
import Foundation

@MainActor
final class TrackingLiveActivityController {
    private var liveActivity: Activity<TrackingActivityAttributes>?
    private let onStopRequested: () -> Void

    // Timestamp of the last `Activity.update()` call actually dispatched, used
    // by `update(...)`'s rate limit below. `nil` means "no update sent yet
    // this session" — reset in `start(activityType:)` so the very next
    // `update(...)` call (the first one of a new session) is never throttled.
    private var lastUpdateDate: Date?

    init(onStopRequested: @escaping () -> Void) {
        self.onStopRequested = onStopRequested
        registerStopNotificationObserver()
    }

    deinit {
        unregisterStopNotificationObserver()
    }

    func start(activityType: String) {
        guard liveActivity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = TrackingActivityAttributes(activityType: activityType)
        let initialState = TrackingActivityAttributes.ContentState(
            distanceMeters: 0,
            elapsedMillis: 0,
            currentSpeedMetersPerSecond: nil
        )

        liveActivity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: initialState, staleDate: nil)
        )
        lastUpdateDate = nil
    }

    // ActivityKit documents a Live Activity update budget of roughly once per
    // second; TrackingViewModel calls this on every location-driven state
    // emission (which can arrive several times a second), and bursting past
    // that budget has been observed to get the whole process SIGKILLed
    // ("Updating content for activity <id>" logged many times in rapid
    // succession, immediately followed by "Debug session ended with code 9:
    // killed"). Rather than have TrackingViewModel throttle its own calls,
    // this silently drops any `update(...)` that arrives sooner than
    // `minimumUpdateInterval` after the last one actually sent — the caller
    // can keep calling on every emission with no awareness of this limit.
    // `lastUpdateDate` starts `nil` each session (reset in `start(activityType:)`),
    // so the first update after a Start is always sent regardless of timing;
    // `end(...)` doesn't go through this method at all, so it's never throttled.
    private static let minimumUpdateInterval: TimeInterval = 1

    func update(distanceMeters: Double, elapsedMillis: Int64, currentSpeedMetersPerSecond: Double?) {
        guard let liveActivity else { return }

        let now = Date()
        if let lastUpdateDate, now.timeIntervalSince(lastUpdateDate) < Self.minimumUpdateInterval {
            return
        }
        lastUpdateDate = now

        let contentState = TrackingActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            elapsedMillis: elapsedMillis,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond
        )

        Task {
            await liveActivity.update(ActivityContent(state: contentState, staleDate: nil))
        }
    }

    // Called once, from onStopClicked() — after `trackingState` has already
    // advanced to `.finished` — with that state's final metrics, so the Live
    // Activity's last-shown content reflects the session's actual totals.
    func end(distanceMeters: Double, elapsedMillis: Int64, currentSpeedMetersPerSecond: Double?) {
        guard let liveActivity else { return }
        self.liveActivity = nil

        let finalState = TrackingActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            elapsedMillis: elapsedMillis,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond
        )

        Task {
            await liveActivity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date(timeIntervalSinceNow: Self.dismissalDelaySeconds))
            )
        }
    }

    private static let dismissalDelaySeconds: TimeInterval = 5

    // MARK: - Stop notification (from the Live Activity's Stop button)

    // The widget extension's StopTrackingIntent runs in its own process and
    // can't reach TrackingSessionManager directly (it's an in-memory Kotlin
    // singleton scoped to the main app process) — it signals over a Darwin
    // notification instead. This observer is what turns that best-effort
    // signal into a real stop, exactly as long as this controller exists to
    // observe it (registered in init, unregistered in deinit).
    private func registerStopNotificationObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<TrackingLiveActivityController>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    controller.onStopRequested()
                }
            },
            TrackingLiveActivityConstants.stopNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    // `nonisolated` so it can run synchronously from `deinit` (deinit on a
    // @MainActor class runs nonisolated) — it only touches a raw pointer to
    // `self` and a system notification center, not any actor-isolated state.
    nonisolated private func unregisterStopNotificationObserver() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(TrackingLiveActivityConstants.stopNotificationName as CFString),
            nil
        )
    }
}
