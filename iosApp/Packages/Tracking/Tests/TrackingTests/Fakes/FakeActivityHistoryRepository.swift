//
//  FakeActivityHistoryRepository.swift
//  TrackingTests
//
//  Only `saveActivity` matters here: the real SaveActivityUseCase is built around this fake.
//

import Foundation
import SharedKit

final class FakeActivityHistoryRepository: NSObject, ActivityHistoryRepository {

    private let lock = NSLock()
    private var recordedSavedActivities: [ActivityRecord] = []

    var savedActivities: [ActivityRecord] {
        lock.withLock { recordedSavedActivities }
    }

    func observeActivities() -> SkieSwiftFlow<[ActivityRecord]> {
        SkieSwiftFlow(SkieKotlinFlow(SwiftTestFlow<NSArray>(values: [savedActivities as NSArray])))
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getActivity`
    func __getActivity(id: Int64) async throws -> ActivityRecord? {
        lock.withLock { recordedSavedActivities.first { $0.id == id } }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun deleteActivity`
    func __deleteActivity(id: Int64) async throws {
        lock.withLock { recordedSavedActivities.removeAll { $0.id == id } }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun saveActivity`
    func __saveActivity(activity: ActivityRecord) async throws -> KotlinLong {
        lock.withLock {
            recordedSavedActivities.append(activity)
            return KotlinLong(value: Int64(recordedSavedActivities.count))
        }
    }
}
