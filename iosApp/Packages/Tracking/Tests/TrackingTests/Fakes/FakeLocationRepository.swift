//
//  FakeLocationRepository.swift
//  TrackingTests
//
//  Follows the pattern documented in HistoryTests/Fakes/FakeActivityHistoryRepository.swift.
//  `observeLocationUpdates()` returns a cold `SwiftTestFlow`, so every collection (each
//  `TrackingSessionManager.start()` and `resume()`) emits the same `updates` again,
//  immediately, and then completes.
//

import Foundation
import SharedKit

final class FakeLocationRepository: NSObject, LocationRepository {

    private let lock = NSLock()
    private let updates: [any LocationUpdate]
    private var recordedObserveCallCount = 0

    /// - Parameter updates: what each `observeLocationUpdates()` collection emits, in order.
    init(updates: [any LocationUpdate] = []) {
        self.updates = updates
    }

    var observeCallCount: Int {
        lock.withLock { recordedObserveCallCount }
    }

    func observeLocationUpdates() -> SkieSwiftFlow<any LocationUpdate> {
        lock.withLock { recordedObserveCallCount += 1 }
        return SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<LocationUpdate>(values: updates)))
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getCurrentLocation`
    func __getCurrentLocation() async throws -> Any? {
        SwiftTestResult.shared.success(value: TrackingFixtures.startPoint)
    }
}
