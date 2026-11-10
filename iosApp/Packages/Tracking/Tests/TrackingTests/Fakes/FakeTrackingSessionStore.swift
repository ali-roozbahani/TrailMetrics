//
//  FakeTrackingSessionStore.swift
//  TrackingTests
//

import Foundation
import SharedKit

/// Holds the stored session in memory, counts the calls and can fail a load or a clear.
final class FakeTrackingSessionStore: NSObject, TrackingSessionStore {

    struct StoreFailure: Error {}

    private let lock = NSLock()
    private var stored: StoredTrackingSession?
    private var isLoadFailing = false
    private var isClearFailing = false
    private var recordedLoadCount = 0
    private var recordedClearCount = 0

    init(stored: StoredTrackingSession? = nil) {
        self.stored = stored
    }

    var storedSession: StoredTrackingSession? { lock.withLock { stored } }
    var loadCount: Int { lock.withLock { recordedLoadCount } }
    var clearCount: Int { lock.withLock { recordedClearCount } }

    func setLoadFailing(_ failing: Bool) { lock.withLock { isLoadFailing = failing } }
    func setClearFailing(_ failing: Bool) { lock.withLock { isClearFailing = failing } }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun save`
    func __save(session: StoredTrackingSession) async throws {
        lock.withLock { stored = session }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun load`
    func __load() async throws -> StoredTrackingSession? {
        try lock.withLock {
            recordedLoadCount += 1
            if isLoadFailing { throw StoreFailure() }
            return stored
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun clear`
    func __clear() async throws {
        try lock.withLock {
            recordedClearCount += 1
            if isClearFailing { throw StoreFailure() }
            stored = nil
        }
    }
}
