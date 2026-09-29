//
//  FakeActivityHistoryRepository.swift
//  HistoryTests
//
//  How iOS ViewModel tests are written in this repo (the pattern other packages copy):
//
//  - XCTest, one `@MainActor final class <Subject>Tests: XCTestCase` per ViewModel, async
//    test methods named `test_<subject>_<expectation>()`. Tests use only the ViewModel's
//    public API (`import <Feature>`, no `@testable`).
//  - Dependencies are hand-written fakes in `Tests/<Feature>Tests/Fakes/`, injected through
//    the ViewModel's default-parameter `init`. No mocking library. A fake is an `NSObject`
//    subclass conforming to the Kotlin interface as exported to Swift (Kotlin/Native needs
//    an Objective-C class to call back into). SKIE hides each Kotlin `suspend` requirement
//    under a `__`-prefixed name (`__getActivity(id:)`) and shows callers an `async` wrapper
//    without the prefix. A fake implements the prefixed name as an `async throws` method.
//    SwiftLint's `identifier_name` rejects the `__` prefix, so each such method gets its
//    own single-line `disable:next identifier_name` command with a reason, as below.
//    That's human-approved for SKIE-mandated names only, never for a whole file or the
//    config. Don't throw from it to simulate a failure: the Kotlin interfaces declare no `@Throws`,
//    so Kotlin treats any error other than cancellation as fatal and the test process dies.
//  - Kotlin calls those members off the main thread, so a fake guards what it records with
//    a lock and exposes it through read-only accessors.
//  - Kotlin coroutine values come from shared's test support (shared/.../testsupport):
//      * a `Flow` return value: `SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<T>(values:)))`.
//        It emits the given values in order and then completes, so
//        `await viewModel.observe()` returns once everything has been delivered. Don't
//        implement `Flow` in Swift: Kotlin rejects emissions that come from Swift.
//      * a `CoroutineScope` (e.g. for a real `TrackingSessionManager`): `SwiftTestScope()`,
//        cancelled with `scope.cancel()` when the test ends.
//  - Awaiting ViewModel work:
//      * an `async` ViewModel method: `await` it directly;
//      * work the ViewModel starts in a fire-and-forget `Task { }` (init loading, `on...`
//        intent methods): `await waitUntil { <observable outcome> }` (see WaitUntil.swift);
//      * a completion closure (`onDeleted:`, `onSaved:`): count calls in the test, wait
//        for the count, then assert it is exactly 1;
//      * one-shot events: start `Task { for await event in viewModel.makeEventsStream() {
//        received.append(event) } }` before triggering the intent, `waitUntil` the event
//        arrives, then cancel the task.
//

import Foundation
import SharedKit

final class FakeActivityHistoryRepository: NSObject, ActivityHistoryRepository {

    private let lock = NSLock()
    private var storedActivities: [ActivityRecord]
    private var recordedDeletedIds: [Int64] = []
    private var recordedRequestedIds: [Int64] = []
    private let emissions: [[ActivityRecord]]

    /// - Parameters:
    ///   - activities: records `getActivity(id:)` can return.
    ///   - emissions: the lists `observeActivities()` emits, in order, before completing.
    init(activities: [ActivityRecord] = [], emissions: [[ActivityRecord]] = []) {
        self.storedActivities = activities
        self.emissions = emissions
    }

    var deletedIds: [Int64] {
        lock.withLock { recordedDeletedIds }
    }

    var requestedIds: [Int64] {
        lock.withLock { recordedRequestedIds }
    }

    func observeActivities() -> SkieSwiftFlow<[ActivityRecord]> {
        SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<NSArray>(values: emissions.map { $0 as NSArray })))
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getActivity`
    func __getActivity(id: Int64) async throws -> ActivityRecord? {
        lock.withLock {
            recordedRequestedIds.append(id)
            return storedActivities.first { $0.id == id }
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun deleteActivity`
    func __deleteActivity(id: Int64) async throws {
        lock.withLock {
            recordedDeletedIds.append(id)
            storedActivities.removeAll { $0.id == id }
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun saveActivity`
    func __saveActivity(activity: ActivityRecord) async throws -> KotlinLong {
        lock.withLock { storedActivities.append(activity) }
        return KotlinLong(value: activity.id)
    }
}
