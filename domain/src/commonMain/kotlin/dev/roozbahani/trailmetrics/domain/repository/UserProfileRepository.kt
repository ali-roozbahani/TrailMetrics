package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.UserProfile
import kotlin.coroutines.cancellation.CancellationException

interface UserProfileRepository {
    @Throws(Exception::class, CancellationException::class)
    suspend fun getUserProfile(): UserProfile?

    @Throws(Exception::class, CancellationException::class)
    suspend fun saveUserProfile(userProfile: UserProfile)
}
