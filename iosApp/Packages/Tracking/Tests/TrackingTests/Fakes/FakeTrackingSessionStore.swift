//
//  FakeTrackingSessionStore.swift
//  TrackingTests
//

import Foundation
import SharedKit

/// Holds the stored session in memory, counts the calls, can fail a load or a clear and can hold a load
/// until `releaseLoad()` (a read that is still running).
final class FakeTrackingSessionStore: NSObject, TrackingSessionStore {

    struct StoreFailure: Error {}

    private let lock = NSLock()
    private var stored: StoredTrackingSession?
    private var isLoadFailing = false
    private var isClearFailing = false
    private var isSaveFailing = false
    private var recordedLoadCount = 0
    private var recordedClearCount = 0
    private var isLoadHeld = false
    private var heldLoads: [CheckedContinuation<Void, Never>] = []

    init(stored: StoredTrackingSession? = nil) {
        self.stored = stored
    }

    var storedSession: StoredTrackingSession? { lock.withLock { stored } }
    var loadCount: Int { lock.withLock { recordedLoadCount } }
    var clearCount: Int { lock.withLock { recordedClearCount } }

    func setLoadFailing(_ failing: Bool) { lock.withLock { isLoadFailing = failing } }
    /// The next loads suspend until `releaseLoad()`.
    func holdLoad() { lock.withLock { isLoadHeld = true } }

    func releaseLoad() {
        let waiting = lock.withLock {
            isLoadHeld = false
            let waiting = heldLoads
            heldLoads = []
            return waiting
        }
        waiting.forEach { $0.resume() }
    }

    /// The number of loads that have started and are held.
    var heldLoadCount: Int { lock.withLock { heldLoads.count } }

    func setClearFailing(_ failing: Bool) { lock.withLock { isClearFailing = failing } }
    /// While set, every save throws `StoreFailure` and stores nothing.
    func setSaveFailing(_ failing: Bool) { lock.withLock { isSaveFailing = failing } }

    // swiftlint:disable:next identifier_name async_without_await - SKIE: `suspend fun save`
    func __save(session: StoredTrackingSession) async throws {
        let isFailing = lock.withLock { () -> Bool in
            if !isSaveFailing { stored = session }
            return isSaveFailing
        }
        if isFailing { throw StoreFailure() }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun load`
    func __load() async throws -> StoredTrackingSession? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let shouldHold = lock.withLock {
                if isLoadHeld { heldLoads.append(continuation) }
                return isLoadHeld
            }
            if !shouldHold { continuation.resume() }
        }
        return try lock.withLock {
            recordedLoadCount += 1
            if isLoadFailing { throw StoreFailure() }
            return stored
        }
    }

    // swiftlint:disable:next identifier_name async_without_await - SKIE: `suspend fun clear`
    func __clear() async throws {
        try lock.withLock {
            recordedClearCount += 1
            if isClearFailing { throw StoreFailure() }
            stored = nil
        }
    }
}
