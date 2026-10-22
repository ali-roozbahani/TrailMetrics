package dev.roozbahani.trailmetrics.data.user

import android.content.Context
import android.content.SharedPreferences
import androidx.test.core.app.ApplicationProvider
import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.StoredUserProfileUnreadableException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class UserProfileRepositoryImplTest {

    private lateinit var repo: UserProfileRepositoryImpl
    private lateinit var prefs: SharedPreferences

    @OptIn(ExperimentalCoroutinesApi::class)
    @Before
    fun setup() {
        val context: Context = ApplicationProvider.getApplicationContext()
        prefs = context.getSharedPreferences("test_prefs", Context.MODE_PRIVATE)
        repo = UserProfileRepositoryImpl(KeyValueStorage(prefs), UnconfinedTestDispatcher())
    }

    @Test
    fun `getUserProfile returns null when nothing is saved`() = runTest {
        val userProfile = repo.getUserProfile()
        assertNull(userProfile)
    }

    @Test
    fun `saveUserProfile then getUserProfile returns the same profile`() = runTest {
        val userProfile = UserProfile(12.00)
        repo.saveUserProfile(userProfile)

        val result = repo.getUserProfile()
        assertEquals(userProfile, result)
    }

    @Test
    fun `getUserProfile throws and keeps the value when the stored JSON is corrupted`() = runTest {
        assertUnreadableAndKept("{ not a valid json")
    }

    @Test
    fun `getUserProfile throws and keeps the value when the stored profile has an older shape`() = runTest {
        assertUnreadableAndKept("""{"weight":70.0}""")
    }

    @Test
    fun `getUserProfile throws and keeps the value when the stored string is empty`() = runTest {
        assertUnreadableAndKept("")
    }

    @Test
    fun `getUserProfile returns a valid stored profile`() = runTest {
        prefs.edit().putString(KEY, """{"weightKg":70.5}""").apply()

        assertEquals(UserProfile(70.5), repo.getUserProfile())
    }

    @Test
    fun `saving a profile after an unreadable one replaces it`() = runTest {
        prefs.edit().putString(KEY, "{ not a valid json").apply()
        assertFailsWith<StoredUserProfileUnreadableException> { repo.getUserProfile() }

        repo.saveUserProfile(UserProfile(80.0))

        assertEquals(UserProfile(80.0), repo.getUserProfile())
    }

    private suspend fun assertUnreadableAndKept(stored: String) {
        prefs.edit().putString(KEY, stored).apply()

        assertFailsWith<StoredUserProfileUnreadableException> { repo.getUserProfile() }

        assertEquals(stored, prefs.getString(KEY, null))
    }

    private companion object {
        const val KEY = "user_profile"
    }
}
