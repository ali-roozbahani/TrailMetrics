//
//  FakeUserProfileRepository.swift
//  TestSupport
//

import Foundation
import SharedKit

public final class FakeUserProfileRepository: NSObject, UserProfileRepository {

    /// What a failing call throws, standing in for a storage failure.
    public struct StorageError: Error {}

    private let lock = NSLock()
    private var storedProfile: UserProfile?
    private var recordedSavedProfiles: [UserProfile] = []
    private var recordedGetCallCount = 0
    private var isFailingStorage: Bool

    /// - Parameter isFailing: whether calls throw `StorageError` until `setFailing(false)`.
    public init(profile: UserProfile? = nil, isFailing: Bool = false) {
        self.storedProfile = profile
        self.isFailingStorage = isFailing
    }

    public var savedProfiles: [UserProfile] {
        lock.withLock { recordedSavedProfiles }
    }

    public var getUserProfileCallCount: Int {
        lock.withLock { recordedGetCallCount }
    }

    /// Makes later calls throw `StorageError` (counted, saving nothing) or work again.
    /// The Kotlin interface declares `@Throws(Exception::class, ...)`, so the throw reaches
    /// the Swift caller as an error instead of terminating the process.
    public func setFailing(_ isFailing: Bool) {
        lock.withLock { isFailingStorage = isFailing }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getUserProfile`
    public func __getUserProfile() async throws -> UserProfile? {
        try lock.withLock {
            recordedGetCallCount += 1
            if isFailingStorage { throw StorageError() }
            return storedProfile
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun saveUserProfile`
    public func __saveUserProfile(userProfile: UserProfile) async throws {
        try lock.withLock {
            if isFailingStorage { throw StorageError() }
            recordedSavedProfiles.append(userProfile)
            storedProfile = userProfile
        }
    }
}
