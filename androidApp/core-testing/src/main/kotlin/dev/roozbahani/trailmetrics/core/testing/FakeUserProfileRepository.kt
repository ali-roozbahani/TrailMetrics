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

    /** When set, [getUserProfile] throws it (after the gate) instead of returning [userProfile]. */
    var getUserProfileFailure: Throwable? = null

    /** When set, [saveUserProfile] throws it instead of storing the profile. */
    var saveUserProfileFailure: Throwable? = null

    val savedProfiles = mutableListOf<UserProfile>()

    override suspend fun getUserProfile(): UserProfile? {
        getUserProfileCalls++
        getUserProfileGate?.await()
        getUserProfileFailure?.let { throw it }
        return userProfile
    }

    override suspend fun saveUserProfile(userProfile: UserProfile) {
        saveUserProfileFailure?.let { throw it }
        savedProfiles += userProfile
        this.userProfile = userProfile
    }
}
