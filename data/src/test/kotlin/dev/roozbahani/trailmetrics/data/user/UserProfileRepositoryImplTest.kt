package dev.roozbahani.trailmetrics.data.user

import android.content.Context
import android.content.SharedPreferences
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

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
        repo = UserProfileRepositoryImpl(prefs, UnconfinedTestDispatcher())
    }

    @Test
    fun `getUserProfile returns null when nothing is saved`() = runTest {
        val userProfile = repo.getUserProfile()
        assertThat(userProfile).isNull()
    }

    @Test
    fun `saveUserProfile then getUserProfile returns the same profile`() = runTest {
        val userProfile = UserProfile(12.00)
        repo.saveUserProfile(userProfile)

        val result = repo.getUserProfile()
        assertThat(result).isEqualTo(userProfile)
    }

    @Test
    fun `getUserProfile returns null when stored JSON is corrupted`() = runTest {
        // Arrange: Store an invalid JSON inside shared prefs
        prefs.edit()
            .putString("user_profile", "{ not a valid json")
            .apply()

        val result = repo.getUserProfile()
        assertThat(result).isNull()
    }

}
