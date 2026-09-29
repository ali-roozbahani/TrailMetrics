//
//  FakeUserProfileRepository.swift
//  RouteTests
//

import Foundation
import SharedKit

final class FakeUserProfileRepository: NSObject, UserProfileRepository {

    private let lock = NSLock()
    private var storedProfile: UserProfile?
    private var recordedSavedProfiles: [UserProfile] = []
    private var recordedGetCallCount = 0

    init(profile: UserProfile? = nil) {
        self.storedProfile = profile
    }

    var savedProfiles: [UserProfile] {
        lock.withLock { recordedSavedProfiles }
    }

    var getUserProfileCallCount: Int {
        lock.withLock { recordedGetCallCount }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun getUserProfile`
    func __getUserProfile() async throws -> UserProfile? {
        lock.withLock {
            recordedGetCallCount += 1
            return storedProfile
        }
    }

    // swiftlint:disable:next identifier_name - SKIE-mandated name for Kotlin `suspend fun saveUserProfile`
    func __saveUserProfile(userProfile: UserProfile) async throws {
        lock.withLock {
            recordedSavedProfiles.append(userProfile)
            storedProfile = userProfile
        }
    }
}
