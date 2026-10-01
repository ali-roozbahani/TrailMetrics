package dev.roozbahani.trailmetrics.core.testing

import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import kotlinx.coroutines.CompletableDeferred

class FakeUserProfileRepository(
    var userProfile: UserProfile? = null
) : UserProfileRepository {
    var getUserProfileCalls: Int = 0
        private set

    /** When set, [getUserProfile] suspends until it is completed, then returns [userProfile]. */
    var getUserProfileGate: CompletableDeferred<Unit>? = null

    val savedProfiles = mutableListOf<UserProfile>()

    override suspend fun getUserProfile(): UserProfile? {
        getUserProfileCalls++
        getUserProfileGate?.await()
        return userProfile
    }

    override suspend fun saveUserProfile(userProfile: UserProfile) {
        savedProfiles += userProfile
        this.userProfile = userProfile
    }
}
