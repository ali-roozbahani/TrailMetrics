//
//  UnsavedSessionWarningObservation.swift
//  Tracking
//

import SharedKit

/// Calls `onRaised` on the main actor each time `manager` raises its unsaved-session warning. The warning stays
/// raised until the View has shown it (`TrackingViewModel.onSessionNotSavedShown()`), so a failure while no screen
/// observed it is shown by the next one. The caller keeps the task and cancels it.
func observeUnsavedSessionWarning(
    of manager: TrackingSessionManager,
    onRaised: @escaping @MainActor () -> Void
) -> Task<Void, Never> {
    Task {
        for await isRaised in manager.unsavedSessionWarning.isRaised where isRaised.boolValue {
            await MainActor.run {
                // A value delivered late, after the View already marked the warning shown, is not offered again.
                if manager.unsavedSessionWarning.isRaised.value.boolValue { onRaised() }
            }
        }
    }
}
