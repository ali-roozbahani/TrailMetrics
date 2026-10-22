package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.UserProfile
import kotlin.coroutines.cancellation.CancellationException

interface UserProfileRepository {
    /**
     * The saved profile, or `null` when none was ever saved.
     *
     * @throws StoredUserProfileUnreadableException when a value is stored but cannot be decoded.
     */
    @Throws(Exception::class, CancellationException::class)
    suspend fun getUserProfile(): UserProfile?

    @Throws(Exception::class, CancellationException::class)
    suspend fun saveUserProfile(userProfile: UserProfile)
}
