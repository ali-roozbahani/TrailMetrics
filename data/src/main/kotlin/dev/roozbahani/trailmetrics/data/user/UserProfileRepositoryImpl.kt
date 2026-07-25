package dev.roozbahani.trailmetrics.data.user

import android.content.SharedPreferences
import androidx.core.content.edit
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

class UserProfileRepositoryImpl(
    private val sharedPreferences: SharedPreferences,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) : UserProfileRepository {

    override suspend fun getUserProfile(): UserProfile? = withContext(ioDispatcher) {
        val json = sharedPreferences.getString(KEY_USER_PROFILE, null) ?: return@withContext null
        runCatching { Json.decodeFromString<UserProfile>(json) }.getOrNull()
    }

    override suspend fun saveUserProfile(userProfile: UserProfile) = withContext(ioDispatcher) {
        val json = Json.encodeToString(userProfile)
        sharedPreferences.edit {
            putString(KEY_USER_PROFILE, json)
        }
    }

    private companion object {
        const val KEY_USER_PROFILE = "user_profile"
    }
}
