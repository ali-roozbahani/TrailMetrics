//
//  UnsavedSessionWarningObservation.swift
//  Tracking
//

import SharedKit

/// Calls `onRaised` on the main actor each time `manager` raises its unsaved-session warning, then marks the
/// warning shown. The manager raises it at most once per session and keeps it as state until it is marked, so a
/// failure while no screen observed it is shown by the next one. The caller keeps the task and cancels it.
func observeUnsavedSessionWarning(
    of manager: TrackingSessionManager,
    onRaised: @escaping @MainActor () -> Void
) -> Task<Void, Never> {
    Task {
        for await isRaised in manager.unsavedSessionWarning.isRaised where isRaised.boolValue {
            await MainActor.run {
                onRaised()
                manager.unsavedSessionWarning.markShown()
            }
        }
    }
}
