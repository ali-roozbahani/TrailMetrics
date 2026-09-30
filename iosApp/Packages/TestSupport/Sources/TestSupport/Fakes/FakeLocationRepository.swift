//
//  FakeLocationRepository.swift
//  TestSupport
//
//  Follows the pattern documented in FakeActivityHistoryRepository.swift.
//  One addition for Kotlin members returning `Result<T>` (`getCurrentLocation()`,
//  `getClosedRoute(...)`): SKIE shows them to Swift as `async throws -> Any?`, and Kotlin
//  casts the returned value to a boxed `kotlin.Result`, which Swift can't build. Return
//  `SwiftTestResult.shared.success(value:)` or `.failure(exception:)` from shared's test
//  support instead. A plain value crashes the test process with a ClassCastException.
//  A failure goes through `failure(exception:)`, never a Swift `throw`.
//
//  `observeLocationUpdates()` returns a cold `SwiftTestFlow`, so every collection (e.g. each
//  `TrackingSessionManager.start()` and `resume()`) emits the same `updates` again,
//  immediately, and then completes.
//

import Foundation
import SharedKit

public final class FakeLocationRepository: NSObject, LocationRepository {

    private let lock = NSLock()
    private var storedResult: Any?
    private let updates: [any LocationUpdate]
    private var recordedCallCount = 0
    private var recordedObserveCallCount = 0

    /// - Parameters:
    ///   - result: a `SwiftTestResult` value `getCurrentLocation()` returns.
    ///   - updates: what each `observeLocationUpdates()` collection emits, in order.
    public init(result: Any?, updates: [any LocationUpdate] = []) {
        self.storedResult = result
        self.updates = updates
    }

    public convenience init(location: Coordinates, updates: [any LocationUpdate] = []) {
        self.init(result: SwiftTestResult.shared.success(value: location), updates: updates)
    }

    public convenience init(failure: RouteError) {
        self.init(result: SwiftTestResult.shared.failure(exception: failure))
    }

    public var getCurrentLocationCallCount: Int {
        lock.withLock { recordedCallCount }
    }

    public var observeCallCount: Int {
        lock.withLock { recordedObserveCallCount }
    }

    /// Changes what later `getCurrentLocation()` calls return.
    public func setLocation(_ location: Coordinates) {
        lock.withLock { storedResult = SwiftTestResult.shared.success(value: location) }
    }

    public func observeLocationUpdates() -> SkieSwiftFlow<any LocationUpdate> {
        lock.withLock { recordedObserveCallCount += 1 }
        return SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<LocationUpdate>(values: updates)))
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getCurrentLocation`
    public func __getCurrentLocation() async throws -> Any? {
        lock.withLock {
            recordedCallCount += 1
            return storedResult
        }
    }
}
