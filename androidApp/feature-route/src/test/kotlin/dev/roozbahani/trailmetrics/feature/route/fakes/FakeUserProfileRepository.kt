package dev.roozbahani.trailmetrics.feature.route.fakes

import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository

class FakeUserProfileRepository(
    var userProfile: UserProfile? = null
) : UserProfileRepository {
    var getUserProfileCalls: Int = 0
        private set

    val savedProfiles = mutableListOf<UserProfile>()

    override suspend fun getUserProfile(): UserProfile? {
        getUserProfileCalls++
        return userProfile
    }

    override suspend fun saveUserProfile(userProfile: UserProfile) {
        savedProfiles += userProfile
        this.userProfile = userProfile
    }
}
