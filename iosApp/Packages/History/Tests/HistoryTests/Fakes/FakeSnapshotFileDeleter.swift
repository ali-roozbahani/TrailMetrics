//
//  FakeSnapshotFileDeleter.swift
//  HistoryTests
//

import History
import os

/// Records the stored paths it is asked to delete. With `isHolding`, a call does not return until
/// `release()`, so a test can look at the state between the call and its return.
final class FakeSnapshotFileDeleter: SnapshotFileDeleting, Sendable {
    private struct State {
        var storedPaths: [String?] = []
        var isHolding: Bool
        var heldCall: CheckedContinuation<Void, Never>?
    }

    private let state: OSAllocatedUnfairLock<State>

    init(isHolding: Bool = false) {
        state = OSAllocatedUnfairLock(initialState: State(isHolding: isHolding))
    }

    var storedPaths: [String?] {
        state.withLock { $0.storedPaths }
    }

    func delete(storedPath: String?) async {
        let shouldHold = state.withLock { state in
            state.storedPaths.append(storedPath)
            return state.isHolding
        }
        guard shouldHold else { return }
        await withCheckedContinuation { call in
            let isAlreadyReleased = state.withLock { state in
                guard state.isHolding else { return true }
                state.heldCall = call
                return false
            }
            if isAlreadyReleased { call.resume() }
        }
    }

    func release() {
        let call = state.withLock { state in
            state.isHolding = false
            defer { state.heldCall = nil }
            return state.heldCall
        }
        call?.resume()
    }
}
