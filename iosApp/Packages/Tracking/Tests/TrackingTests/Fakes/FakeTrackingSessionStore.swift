//
//  FakeTrackingSessionStore.swift
//  TrackingTests
//

import Foundation
import SharedKit

/// Keeps nothing: the ViewModel tests do not cover the stored session, which is restored by a later task.
final class FakeTrackingSessionStore: NSObject, TrackingSessionStore {

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun save`
    func __save(state: TrackingState) async throws {}

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun load`
    func __load() async throws -> TrackingState? { nil }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun clear`
    func __clear() async throws {}
}
