//
//  FakeDirectionsRepository.swift
//  RouteTests
//

import Foundation
import SharedKit

final class FakeDirectionsRepository: NSObject, DirectionsRepository {

    struct Request: Equatable {
        let startPoint: Coordinates
        let waypoints: [Coordinates]
    }

    private let lock = NSLock()
    private let result: Any?
    private var recordedRequests: [Request] = []

    /// - Parameter result: a `SwiftTestResult` value `getClosedRoute(...)` returns
    ///   (see FakeLocationRepository.swift).
    init(result: Any?) {
        self.result = result
    }

    convenience init(route: Route) {
        self.init(result: SwiftTestResult.shared.success(value: route))
    }

    convenience init(failure: RouteError) {
        self.init(result: SwiftTestResult.shared.failure(exception: failure))
    }

    var requests: [Request] {
        lock.withLock { recordedRequests }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getClosedRoute`
    func __getClosedRoute(startPoint: Coordinates, waypoints: [Coordinates]) async throws -> Any? {
        lock.withLock {
            recordedRequests.append(Request(startPoint: startPoint, waypoints: waypoints))
            return result
        }
    }
}
