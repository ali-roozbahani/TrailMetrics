//
//  FakeLocationRepository.swift
//  RouteTests
//
//  Follows the pattern documented in HistoryTests/Fakes/FakeActivityHistoryRepository.swift.
//  One addition for Kotlin members returning `Result<T>` (`getCurrentLocation()`,
//  `getClosedRoute(...)`): SKIE shows them to Swift as `async throws -> Any?`, and Kotlin
//  casts the returned value to a boxed `kotlin.Result`, which Swift can't build. Return
//  `SwiftTestResult.shared.success(value:)` or `.failure(exception:)` from shared's test
//  support instead. A plain value crashes the test process with a ClassCastException.
//  A failure goes through `failure(exception:)`, never a Swift `throw`.
//

import Foundation
import SharedKit

final class FakeLocationRepository: NSObject, LocationRepository {

    private let lock = NSLock()
    private var storedResult: Any?
    private var recordedCallCount = 0

    /// - Parameter result: a `SwiftTestResult` value `getCurrentLocation()` returns.
    init(result: Any?) {
        self.storedResult = result
    }

    convenience init(location: Coordinates) {
        self.init(result: SwiftTestResult.shared.success(value: location))
    }

    convenience init(failure: RouteError) {
        self.init(result: SwiftTestResult.shared.failure(exception: failure))
    }

    var getCurrentLocationCallCount: Int {
        lock.withLock { recordedCallCount }
    }

    /// Changes what later `getCurrentLocation()` calls return.
    func setLocation(_ location: Coordinates) {
        lock.withLock { storedResult = SwiftTestResult.shared.success(value: location) }
    }

    func observeLocationUpdates() -> SkieSwiftFlow<any LocationUpdate> {
        SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<LocationUpdate>(values: [])))
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getCurrentLocation`
    func __getCurrentLocation() async throws -> Any? {
        lock.withLock {
            recordedCallCount += 1
            return storedResult
        }
    }
}
