//
//  FakeActivityHistoryRepository.swift
//  TestSupport
//
//  How iOS ViewModel tests are written in this repo (the pattern other packages copy):
//
//  - XCTest, one `@MainActor final class <Subject>Tests: XCTestCase` per ViewModel, async
//    test methods named `test_<subject>_<expectation>()`. Tests use only the ViewModel's
//    public API (`import <Feature>`, no `@testable`).
//  - Dependencies are hand-written fakes, injected through the ViewModel's
//    default-parameter `init`. No mocking library. A fake of a domain interface that two or
//    more feature packages need lives here in TestSupport (public, `import TestSupport`);
//    a fake only one feature needs stays in that feature's `Tests/<Feature>Tests/Fakes/`.
//    TestSupport is a dependency of `.testTarget`s only, never of a Sources/ target.
//    A fake is an `NSObject` subclass conforming to the Kotlin interface as exported to
//    Swift (Kotlin/Native needs an Objective-C class to call back into). SKIE hides each Kotlin `suspend` requirement
//    under a `__`-prefixed name (`__getActivity(id:)`) and shows callers an `async` wrapper
//    without the prefix. A fake implements the prefixed name as an `async throws` method.
//    SwiftLint's `identifier_name` rejects the `__` prefix, so each such method gets its
//    own single-line `disable:next identifier_name` command with a reason, as below.
//    That's human-approved for SKIE-mandated names only, never for a whole file or the
//    config. Throw from it to simulate a failure only if the Kotlin member declares `@Throws`
//    (`UserProfileRepository` and `ActivityHistoryRepository`'s suspend members do, see
//    `FakeUserProfileRepository.setFailing`): otherwise Kotlin treats any error other than
//    cancellation as fatal and the test process dies.
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

public final class FakeActivityHistoryRepository: NSObject, ActivityHistoryRepository {

    /// What a failing call throws, standing in for a storage failure.
    public struct StorageError: Error {}

    private let lock = NSLock()
    private var storedActivities: [ActivityRecord]
    private var recordedSavedActivities: [ActivityRecord] = []
    private var recordedDeletedIds: [Int64] = []
    private var recordedRequestedIds: [Int64] = []
    private let emissions: [[ActivityRecord]]
    private var isFailingStorage = false

    /// - Parameters:
    ///   - activities: records `getActivity(id:)` can return. Saved activities are added.
    ///   - emissions: the lists `observeActivities()` emits, in order, before completing.
    public init(activities: [ActivityRecord] = [], emissions: [[ActivityRecord]] = []) {
        self.storedActivities = activities
        self.emissions = emissions
    }

    /// Every activity passed to `saveActivity`, in order.
    public var savedActivities: [ActivityRecord] {
        lock.withLock { recordedSavedActivities }
    }

    public var deletedIds: [Int64] {
        lock.withLock { recordedDeletedIds }
    }

    public var requestedIds: [Int64] {
        lock.withLock { recordedRequestedIds }
    }

    /// Makes later suspend calls throw `StorageError` (recording and changing nothing) or work
    /// again. Every suspend member declares `@Throws`, as `FakeUserProfileRepository.setFailing`
    /// describes.
    public func setFailing(_ isFailing: Bool) {
        lock.withLock { isFailingStorage = isFailing }
    }

    public func observeActivities() -> SkieSwiftFlow<[ActivityRecord]> {
        SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<NSArray>(values: emissions.map { $0 as NSArray })))
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getActivity`
    public func __getActivity(id: Int64) async throws -> ActivityRecord? {
        try lock.withLock {
            if isFailingStorage { throw StorageError() }
            recordedRequestedIds.append(id)
            return storedActivities.first { $0.id == id }
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun deleteActivity`
    public func __deleteActivity(id: Int64) async throws {
        try lock.withLock {
            if isFailingStorage { throw StorageError() }
            recordedDeletedIds.append(id)
            storedActivities.removeAll { $0.id == id }
        }
    }

    // Returns the save count as the new id, like an auto-incrementing primary key.
    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun saveActivity`
    public func __saveActivity(activity: ActivityRecord) async throws -> KotlinLong {
        try lock.withLock {
            if isFailingStorage { throw StorageError() }
            recordedSavedActivities.append(activity)
            storedActivities.append(activity)
            return KotlinLong(value: Int64(recordedSavedActivities.count))
        }
    }
}
