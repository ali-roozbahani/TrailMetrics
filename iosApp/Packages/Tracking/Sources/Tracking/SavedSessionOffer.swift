//
//  SavedSessionOffer.swift
//  Tracking
//

import Foundation
import SharedKit

/// What the app offers for the session that `TrackingSessionManager.restore()` returned, the same rule as
/// Android's `SavedSessionOfferViewModel.offerFor`: a Paused or Finished session with a recorded path is
/// offered as the Tracking route (start point = first path point, no planned route); Idle and Tracking
/// (a session that is live in this process) are never offered.
///
/// - Parameter fallbackActivityType: used for a session stored before the type was saved.
func savedSessionOffer(
    for restored: TrackingState,
    activityType: ActivityType?,
    fallbackActivityType: ActivityType = .running
) -> AppRouteTracking? {
    let path: [Coordinates]
    switch onEnum(of: restored) {
    case .paused(let data): path = data.metrics.path
    case .finished(let data): path = data.metrics.path
    case .idle, .tracking: return nil
    }
    guard let startPoint = path.first else { return nil }
    return AppRouteTracking(
        startPoint: startPoint,
        plannedRoutePoints: [],
        selectedActivityType: activityType ?? fallbackActivityType
    )
}

/// Restores the stored tracking session once per app launch and publishes the Tracking route to offer.
/// The offer stays published until `offerConsumed()`, so a view that is rebuilt does not lose it, and the
/// model never offers a second time.
@MainActor
public final class SavedSessionOfferModel: ObservableObject {
    @Published public private(set) var offer: AppRouteTracking?
    /// The stored session could not be read: nothing is offered, and it stays stored for the next start.
    @Published public private(set) var restoreFailed = false

    private let trackingSessionManager: TrackingSessionManager
    private let endOrphanedLiveActivities: () async -> Void
    private var hasRestored = false

    public convenience init(trackingSessionManager: TrackingSessionManager = KoinHelper().trackingSessionManager()) {
        self.init(trackingSessionManager: trackingSessionManager) {
            await Tracking.endOrphanedLiveActivities()
        }
    }

    init(
        trackingSessionManager: TrackingSessionManager,
        endOrphanedLiveActivities: @escaping () async -> Void
    ) {
        self.trackingSessionManager = trackingSessionManager
        self.endOrphanedLiveActivities = endOrphanedLiveActivities
    }

    /// Does nothing after the first call. `restore()` is a Kotlin suspend function: the store read runs
    /// off the main actor, so the main actor is only resumed with the result.
    public func restoreOnce() async {
        guard !hasRestored else { return }
        hasRestored = true
        // No session is live in a freshly started process, so a Live Activity that exists belongs to a killed
        // one: end it before the restored session is offered, so a Resume does not leave two on the lock screen.
        await endOrphanedLiveActivities()
        do {
            let restored = try await trackingSessionManager.restore()
            offer = savedSessionOffer(
                for: restored,
                activityType: trackingSessionManager.sessionDetails.value?.activityType
            )
        } catch is CancellationError {
            // The launch task was cancelled before the read finished: nothing failed, so no alert, and
            // the next run of the task restores.
            hasRestored = false
        } catch {
            restoreFailed = true
        }
    }

    public func offerConsumed() {
        offer = nil
    }

    public func restoreFailureAcknowledged() {
        restoreFailed = false
    }
}
