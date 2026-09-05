package dev.roozbahani.trailmetrics.data.user

import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

class UserProfileRepositoryImpl(
    private val storage: KeyValueStorage,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) : UserProfileRepository {

    override suspend fun getUserProfile(): UserProfile? = withContext(ioDispatcher) {
        val json = storage.getString(KEY_USER_PROFILE) ?: return@withContext null
        runCatching { Json.decodeFromString<UserProfile>(json) }.getOrNull()
    }

    override suspend fun saveUserProfile(userProfile: UserProfile) = withContext(ioDispatcher) {
        val json = Json.encodeToString(userProfile)
        storage.putString(KEY_USER_PROFILE, json)
    }

    private companion object {
        const val KEY_USER_PROFILE = "user_profile"
    }
}
