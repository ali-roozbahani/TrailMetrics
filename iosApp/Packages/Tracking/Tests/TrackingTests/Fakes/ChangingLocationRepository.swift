//
//  ChangingLocationRepository.swift
//  TrackingTests
//
//  Like TestSupport's FakeLocationRepository (see the notes there on `Result` and the cold flow), but what
//  the next collection emits can change: a test pauses a session, then decides which fix the Resume delivers.
//

import Foundation
import SharedKit
import TestSupport

final class ChangingLocationRepository: NSObject, LocationRepository {

    private let lock = NSLock()
    private let location: Coordinates
    private var updates: [any LocationUpdate]

    init(location: Coordinates, updates: [any LocationUpdate]) {
        self.location = location
        self.updates = updates
    }

    /// What every later `observeLocationUpdates()` collection (Start, Resume) emits.
    func setUpdates(_ newUpdates: [any LocationUpdate]) {
        lock.withLock { updates = newUpdates }
    }

    func observeLocationUpdates() -> SkieSwiftFlow<any LocationUpdate> {
        let current = lock.withLock { updates }
        return SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<LocationUpdate>(values: current)))
    }

    // swiftlint:disable:next identifier_name async_without_await - SKIE: `suspend fun getCurrentLocation`
    func __getCurrentLocation() async throws -> Any? {
        SwiftTestResult.shared.success(value: location)
    }
}
