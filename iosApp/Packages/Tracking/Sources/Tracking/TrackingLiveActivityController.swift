//
//  TrackingLiveActivityController.swift
//  Tracking
//
//  Owns the Live Activity's lifecycle (request/update/end) and the Darwin
//  notification observer for its Stop button. Kept out of TrackingViewModel
//  so that class stays focused on tracking state itself.
//

import Foundation

@MainActor
final class TrackingLiveActivityController {
    // The id of the Activity this controller requested. Every other Activity of the attributes type is an
    // orphan of a killed process: `start` and `end` end those too.
    private var ownActivityID: String?
    private let client: LiveActivityClient
    private let onStopRequested: () -> Void
    private let now: () -> Date
    private let uptime: () -> ContinuousClock.Instant

    // Monotonic time of the last `Activity.update()` call actually dispatched, used
    // by `update(...)`'s rate limit below (never the wall clock: a system time set back
    // would drop every update until the wall clock caught up). `nil` means "no update
    // sent yet this session" — reset in `start(activityType:)` so the very next
    // `update(...)` call (the first one of a new session) is never throttled.
    private var lastUpdateUptime: ContinuousClock.Instant?
    private var lastUpdateWasPaused = false

    init(
        client: LiveActivityClient = ActivityKitLiveActivityClient(),
        now: @escaping () -> Date = Date.init,
        uptime: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
        onStopRequested: @escaping () -> Void
    ) {
        self.client = client
        self.now = now
        self.uptime = uptime
        self.onStopRequested = onStopRequested
        registerStopNotificationObserver()
    }

    deinit {
        unregisterStopNotificationObserver()
    }

    /// Starts the session's Live Activity and ends every other one the system holds for the app (the one of
    /// a killed process after a restore). The existing ids are read before the request, so the new Activity
    /// is never among those ended.
    func start(activityType: String) {
        if let ownActivityID, client.existingIDs.contains(ownActivityID) { return }
        guard client.areActivitiesEnabled else { return }

        let orphanIDs = client.existingIDs
        ownActivityID = client.request(
            activityType: activityType,
            state: contentState(distanceMeters: 0, elapsedMillis: 0, currentSpeedMetersPerSecond: nil, isPaused: false),
            staleDate: staleDate(isPaused: false)
        )
        lastUpdateUptime = nil
        lastUpdateWasPaused = false

        Task { [client] in
            for id in orphanIDs {
                await client.end(id: id, finalState: nil, dismissal: .immediate)
            }
        }
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
    // `lastUpdateUptime` starts `nil` each session (reset in `start(activityType:)`),
    // so the first update after a Start is always sent regardless of timing;
    // `end(...)` doesn't go through this method at all, so it's never throttled.
    private static let minimumUpdateInterval: Duration = .seconds(1)

    /// How long a sent state counts as current. The system marks the Activity stale after it, and the widget
    /// shows the distance and speed as old, until the next update.
    static let staleInterval: TimeInterval = 120

    func update(distanceMeters: Double, elapsedMillis: Int64, currentSpeedMetersPerSecond: Double?, isPaused: Bool) {
        guard let ownActivityID else { return }

        let sentAt = uptime()
        // A change between Running and Paused is sent at once: the timer would otherwise keep running (or
        // stay held) on the lock screen until the next update, and a paused session sends none.
        let isTransition = isPaused != lastUpdateWasPaused
        if !isTransition, let lastUpdateUptime, sentAt - lastUpdateUptime < Self.minimumUpdateInterval {
            return
        }
        lastUpdateUptime = sentAt
        lastUpdateWasPaused = isPaused

        let state = contentState(
            distanceMeters: distanceMeters,
            elapsedMillis: elapsedMillis,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
            isPaused: isPaused
        )

        Task { [client] in
            await client.update(id: ownActivityID, state: state, staleDate: staleDate(isPaused: isPaused))
        }
    }

    /// The timer is anchored to a date, so the system draws the elapsed time on its own: the start is now
    /// minus the elapsed time, and while paused the timer is held at now.
    private func contentState(
        distanceMeters: Double,
        elapsedMillis: Int64,
        currentSpeedMetersPerSecond: Double?,
        isPaused: Bool
    ) -> TrackingActivityAttributes.ContentState {
        let reference = now()
        return TrackingActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
            timerStart: reference.addingTimeInterval(-Double(elapsedMillis) / 1000),
            pausedAt: isPaused ? reference : nil
        )
    }

    /// While running, updates arrive about once a second, so one that stops for `staleInterval` means the
    /// app is not updating (no signal, or the process is gone). A paused session sends none by design.
    private func staleDate(isPaused: Bool) -> Date? {
        isPaused ? nil : now().addingTimeInterval(Self.staleInterval)
    }

    // Called once, from onStopClicked() — after `trackingState` has already
    // advanced to `.finished` — with that state's final metrics, so the Live
    // Activity's last-shown content reflects the session's actual totals.
    func end(distanceMeters: Double, elapsedMillis: Int64, currentSpeedMetersPerSecond: Double?) {
        let ownID = ownActivityID
        ownActivityID = nil
        let ids = client.existingIDs

        let finalState = contentState(
            distanceMeters: distanceMeters,
            elapsedMillis: elapsedMillis,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
            isPaused: true
        )

        // This controller's Activity keeps the final totals for a few seconds; any other one (an orphan of
        // a killed process) goes at once.
        Task { [client] in
            for id in ids {
                if id == ownID {
                    await client.end(
                        id: id,
                        finalState: finalState,
                        dismissal: .afterDelay(Self.dismissalDelaySeconds)
                    )
                } else {
                    await client.end(id: id, finalState: nil, dismissal: .immediate)
                }
            }
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
