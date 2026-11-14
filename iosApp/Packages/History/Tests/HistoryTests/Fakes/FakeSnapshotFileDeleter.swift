//
//  FakeSnapshotFileDeleter.swift
//  HistoryTests
//

import Foundation
import SharedKit

/// Records the stored paths it is asked to delete. With `isHolding`, a call does not return until
/// `release()`, so a test can look at the state between the call and its return. It cannot throw:
/// the interface's `@Throws` lets only a Kotlin `CancellationException` across the boundary, and a
/// Swift fake has no way to throw one (any error it throws ends the process).
final class FakeSnapshotFileDeleter: NSObject, SnapshotFileDeleter {

    private let lock = NSLock()
    private var recordedPaths: [String?] = []
    private var isHolding: Bool
    private var heldCall: CheckedContinuation<Void, Never>?

    private var recordedResolutions: [String?] = []
    private let resolvedPath: String?

    /// `resolvedPath` is what `resolve` answers for every stored path.
    init(isHolding: Bool = false, resolvedPath: String? = nil) {
        self.isHolding = isHolding
        self.resolvedPath = resolvedPath
    }

    /// The stored paths `resolve` was asked about.
    var resolvedStoredPaths: [String?] { lock.withLock { recordedResolutions } }

    func resolve(storedPath: String?) -> String? {
        lock.withLock { recordedResolutions.append(storedPath) }
        return resolvedPath
    }

    var storedPaths: [String?] { lock.withLock { recordedPaths } }

    func release() {
        let call = lock.withLock {
            isHolding = false
            defer { heldCall = nil }
            return heldCall
        }
        call?.resume()
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun delete`
    func __delete(storedPath: String?) async throws {
        lock.withLock { recordedPaths.append(storedPath) }
        await withCheckedContinuation { (call: CheckedContinuation<Void, Never>) in
            let mustWait = lock.withLock {
                guard isHolding else { return false }
                heldCall = call
                return true
            }
            if !mustWait { call.resume() }
        }
    }
}
