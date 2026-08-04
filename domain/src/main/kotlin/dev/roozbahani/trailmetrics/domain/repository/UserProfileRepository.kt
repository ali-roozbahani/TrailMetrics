package dev.roozbahani.trailmetrics.domain.repository

import dev.roozbahani.trailmetrics.domain.model.UserProfile

interface UserProfileRepository {
    suspend fun getUserProfile(): UserProfile?
    suspend fun saveUserProfile(userProfile: UserProfile)
}
