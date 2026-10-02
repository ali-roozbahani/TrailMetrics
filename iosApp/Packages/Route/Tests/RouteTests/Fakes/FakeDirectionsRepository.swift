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
    private let results: [Any?]
    private var recordedRequests: [Request] = []
    private var completedCount = 0
    private var isHoldingRequests = false
    private var heldRequests: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releasedIndices: Set<Int> = []

    /// - Parameter results: the `SwiftTestResult` values (see TestSupport's
    ///   FakeLocationRepository.swift) `getClosedRoute(...)` returns, one per request in
    ///   order; the last one repeats for later requests.
    init(results: [Any?]) {
        precondition(!results.isEmpty, "FakeDirectionsRepository needs at least one result")
        self.results = results
    }

    convenience init(route: Route) {
        self.init(routes: [route])
    }

    convenience init(routes: [Route]) {
        self.init(results: routes.map { SwiftTestResult.shared.success(value: $0) })
    }

    convenience init(failure: RouteError) {
        self.init(results: [SwiftTestResult.shared.failure(exception: failure)])
    }

    var requests: [Request] {
        lock.withLock { recordedRequests }
    }

    /// How many requests have returned their result to the caller.
    var completedRequestCount: Int {
        lock.withLock { completedCount }
    }

    /// Makes every later request wait (still recorded) until `release(requestAt:)` or
    /// `releaseAll()` lets it return.
    func holdRequests() {
        lock.withLock { isHoldingRequests = true }
    }

    /// Lets the `index`-th request (0-based, in arrival order) return, now or when it arrives.
    func release(requestAt index: Int) {
        let continuation = lock.withLock {
            releasedIndices.insert(index)
            return heldRequests.removeValue(forKey: index)
        }
        continuation?.resume()
    }

    /// Stops holding and lets every held request return.
    func releaseAll() {
        let continuations = lock.withLock {
            isHoldingRequests = false
            defer { heldRequests = [:] }
            return Array(heldRequests.values)
        }
        continuations.forEach { $0.resume() }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getClosedRoute`
    func __getClosedRoute(startPoint: Coordinates, waypoints: [Coordinates]) async throws -> Any? {
        let index = lock.withLock {
            recordedRequests.append(Request(startPoint: startPoint, waypoints: waypoints))
            return recordedRequests.count - 1
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let mustWait = lock.withLock {
                guard isHoldingRequests, !releasedIndices.contains(index) else { return false }
                heldRequests[index] = continuation
                return true
            }
            if !mustWait { continuation.resume() }
        }
        return lock.withLock {
            completedCount += 1
            return results[min(index, results.count - 1)]
        }
    }
}
