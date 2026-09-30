package dev.roozbahani.trailmetrics.feature.tracking.fakes

import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository

class FakeUserProfileRepository(
    var userProfile: UserProfile? = null
) : UserProfileRepository {
    override suspend fun getUserProfile(): UserProfile? = userProfile

    override suspend fun saveUserProfile(userProfile: UserProfile) {
        this.userProfile = userProfile
    }
}
