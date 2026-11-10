//
//  LiveActivityClient.swift
//  Tracking
//
//  The seam between TrackingLiveActivityController and ActivityKit, so the controller's rules (which
//  activities to end, in which order) can be tested without ActivityKit. ActivityKit itself is not faked:
//  `ActivityKitLiveActivityClient` is covered by the human check of the PR.
//

import ActivityKit
import Foundation

enum LiveActivityDismissal: Equatable {
    case immediate
    case afterDelay(TimeInterval)
}

@MainActor
protocol LiveActivityClient {
    var areActivitiesEnabled: Bool { get }
    /// The ids of every Activity of `TrackingActivityAttributes` the system holds for this app,
    /// including those of a process that was killed.
    var existingIDs: [String] { get }
    /// The id of the new Activity, or nil when the system refuses one.
    func request(activityType: String) -> String?
    func update(id: String, state: TrackingActivityAttributes.ContentState) async
    func end(id: String, finalState: TrackingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async
}

@MainActor
struct ActivityKitLiveActivityClient: LiveActivityClient {
    nonisolated init() {}

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    var existingIDs: [String] { Activity<TrackingActivityAttributes>.activities.map(\.id) }

    func request(activityType: String) -> String? {
        let attributes = TrackingActivityAttributes(activityType: activityType)
        let initialState = TrackingActivityAttributes.ContentState(
            distanceMeters: 0,
            elapsedMillis: 0,
            currentSpeedMetersPerSecond: nil
        )
        // Silent on purpose: the Live Activity is an optional extra (the user can turn Live
        // Activities off, or the system can refuse one), and tracking works without it.
        // An exception to `tm-ios`'s "never drop an error" rule.
        // swiftlint:disable:next optional_try - the Live Activity is optional; nil leaves tracking running without it
        let activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: initialState, staleDate: nil)
        )
        return activity?.id
    }

    func update(id: String, state: TrackingActivityAttributes.ContentState) async {
        await activity(id: id)?.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(id: String, finalState: TrackingActivityAttributes.ContentState?, dismissal: LiveActivityDismissal) async {
        let policy: ActivityUIDismissalPolicy
        switch dismissal {
        case .immediate: policy = .immediate
        case .afterDelay(let seconds): policy = .after(Date(timeIntervalSinceNow: seconds))
        }
        await activity(id: id)?.end(
            finalState.map { ActivityContent(state: $0, staleDate: nil) },
            dismissalPolicy: policy
        )
    }

    private func activity(id: String) -> Activity<TrackingActivityAttributes>? {
        Activity<TrackingActivityAttributes>.activities.first { $0.id == id }
    }
}

/// Ends every Live Activity of this app at once. At app launch no session is live in the new process, so
/// any Activity that exists belongs to a killed process and would otherwise stay on the lock screen.
@MainActor
func endOrphanedLiveActivities(client: LiveActivityClient = ActivityKitLiveActivityClient()) async {
    for id in client.existingIDs {
        await client.end(id: id, finalState: nil, dismissal: .immediate)
    }
}
