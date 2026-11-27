//
//  TrackingViewModel+DiscardFinished.swift
//  Tracking
//
//  Discard of a Finished session from the finish card: deleted without saving, and the screen stays.
//

import SharedKit

extension TrackingViewModel {

    /// A Finished session can also be deleted without saving it (`domain`'s `canDiscard`). Not while a Finish
    /// saves it, while its discard runs, or while the screen leaves through Stop (`isDiscarding`).
    public var canDiscardFinished: Bool {
        controls.canDiscard && !isSessionSaved && !isDiscardingFinished && !isDiscarding
    }

    /// The user confirmed deleting the Finished session instead of saving it. The screen stays (`isDiscarding`
    /// is not set): the manager's `discard()` clears the stored session and returns the state to Idle, which the
    /// observation delivers, and Start is offered again.
    public func onDiscardFinishedClicked() {
        guard canDiscardFinished else { return }
        markDiscardingFinished(true)
        Task {
            await clearStoredSession()
            markDiscardingFinished(false)
        }
    }
}
