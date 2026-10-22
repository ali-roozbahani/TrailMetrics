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
    private var isStoredProfileUnreadable = false
    private var isHoldingReads = false
    private var heldReads: [CheckedContinuation<Void, Never>] = []

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

    /// Makes later `getUserProfile` calls throw the Kotlin `StoredUserProfileUnreadableException` (as
    /// the real repository does for a stored value that cannot be decoded) until a profile is
    /// saved, which replaces the broken value, or `setUnreadable(false)`.
    public func setUnreadable(_ isUnreadable: Bool) {
        lock.withLock { isStoredProfileUnreadable = isUnreadable }
    }

    /// Replaces the stored profile that later `getUserProfile` calls return.
    public func setProfile(_ profile: UserProfile?) {
        lock.withLock { storedProfile = profile }
    }

    /// Makes every later `getUserProfile` call wait (already counted) until `releaseReads()`.
    public func holdReads() {
        lock.withLock { isHoldingReads = true }
    }

    /// Stops holding and lets every held `getUserProfile` call return, failing or not as
    /// `setFailing` says by then.
    public func releaseReads() {
        let continuations = lock.withLock {
            isHoldingReads = false
            defer { heldReads = [] }
            return heldReads
        }
        continuations.forEach { $0.resume() }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getUserProfile`
    public func __getUserProfile() async throws -> UserProfile? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let mustWait = lock.withLock {
                recordedGetCallCount += 1
                guard isHoldingReads else { return false }
                heldReads.append(continuation)
                return true
            }
            if !mustWait { continuation.resume() }
        }
        return try lock.withLock {
            if isFailingStorage { throw StorageError() }
            if isStoredProfileUnreadable {
                // The shape SKIE gives a thrown Kotlin exception: an NSError carrying it in userInfo.
                throw NSError(
                    domain: "KotlinException",
                    code: 0,
                    userInfo: ["KotlinException": StoredUserProfileUnreadableException(cause: nil)]
                )
            }
            return storedProfile
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun saveUserProfile`
    public func __saveUserProfile(userProfile: UserProfile) async throws {
        try lock.withLock {
            if isFailingStorage { throw StorageError() }
            recordedSavedProfiles.append(userProfile)
            storedProfile = userProfile
            isStoredProfileUnreadable = false
        }
    }
}
