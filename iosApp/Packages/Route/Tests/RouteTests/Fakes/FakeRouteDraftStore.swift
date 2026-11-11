//
//  FakeRouteDraftStore.swift
//  RouteTests
//

import Foundation
import SharedKit

/// Holds the stored draft in memory with the store's contract (an empty draft clears), records every
/// save, and can fail a load or a save or hold a load until `releaseLoad()`.
final class FakeRouteDraftStore: NSObject, RouteDraftStore {

    struct StoreFailure: Error {}

    private let lock = NSLock()
    private var stored: StoredRouteDraft?
    private var recordedSaves: [StoredRouteDraft] = []
    private var recordedLoadCount = 0
    private var recordedClearCount = 0
    private var isLoadFailing = false
    private var isSaveFailing = false
    private var isHoldingLoad = false
    private var heldLoad: CheckedContinuation<Void, Never>?

    init(stored: StoredRouteDraft? = nil) {
        self.stored = stored
    }

    var storedDraft: StoredRouteDraft? { lock.withLock { stored } }
    var savedDrafts: [StoredRouteDraft] { lock.withLock { recordedSaves } }
    var loadCount: Int { lock.withLock { recordedLoadCount } }
    var clearCount: Int { lock.withLock { recordedClearCount } }

    func setLoadFailing(_ failing: Bool) { lock.withLock { isLoadFailing = failing } }
    func setSaveFailing(_ failing: Bool) { lock.withLock { isSaveFailing = failing } }

    /// Makes the next load wait until `releaseLoad()`.
    func holdLoad() { lock.withLock { isHoldingLoad = true } }

    func releaseLoad() {
        let continuation = lock.withLock {
            isHoldingLoad = false
            defer { heldLoad = nil }
            return heldLoad
        }
        continuation?.resume()
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun save`
    func __save(draft: StoredRouteDraft) async throws {
        try lock.withLock {
            if isSaveFailing { throw StoreFailure() }
            recordedSaves.append(draft)
            stored = draft.isEmpty ? nil : draft
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun load`
    func __load() async throws -> StoredRouteDraft? {
        lock.withLock { recordedLoadCount += 1 }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let mustWait = lock.withLock {
                guard isHoldingLoad else { return false }
                heldLoad = continuation
                return true
            }
            if !mustWait { continuation.resume() }
        }
        return try lock.withLock {
            if isLoadFailing { throw StoreFailure() }
            return stored
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun clear`
    func __clear() async throws {
        lock.withLock {
            recordedClearCount += 1
            stored = nil
        }
    }
}
