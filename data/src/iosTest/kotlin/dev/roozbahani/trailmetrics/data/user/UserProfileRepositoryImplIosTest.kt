package dev.roozbahani.trailmetrics.data.user

import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.StoredUserProfileUnreadableException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import platform.Foundation.NSUserDefaults
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/** The same stored-value cases as the Android host test, on the real [KeyValueStorage] (NSUserDefaults). */
class UserProfileRepositoryImplIosTest {

    private val defaults = NSUserDefaults.standardUserDefaults
    // UnconfinedTestDispatcher has no stable replacement
    @OptIn(ExperimentalCoroutinesApi::class)
    private val repo = UserProfileRepositoryImpl(KeyValueStorage(), UnconfinedTestDispatcher())

    @BeforeTest
    fun clear() = defaults.removeObjectForKey(KEY)

    @AfterTest
    fun cleanUp() = defaults.removeObjectForKey(KEY)

    @Test
    fun `getUserProfile returns null when nothing is saved`() = runTest {
        assertNull(repo.getUserProfile())
    }

    @Test
    fun `getUserProfile returns a valid stored profile`() = runTest {
        defaults.setObject("""{"weightKg":70.5}""", KEY)

        assertEquals(UserProfile(70.5), repo.getUserProfile())
    }

    @Test
    fun `getUserProfile throws and keeps the value for a corrupt or older-shape or empty string`() = runTest {
        listOf("{ not a valid json", """{"weight":70.0}""", "").forEach { stored ->
            defaults.setObject(stored, KEY)

            assertFailsWith<StoredUserProfileUnreadableException> { repo.getUserProfile() }

            assertEquals(stored, defaults.stringForKey(KEY))
        }
    }

    @Test
    fun `saving a profile after an unreadable one replaces it`() = runTest {
        defaults.setObject("{ not a valid json", KEY)
        assertFailsWith<StoredUserProfileUnreadableException> { repo.getUserProfile() }

        repo.saveUserProfile(UserProfile(80.0))

        assertEquals(UserProfile(80.0), repo.getUserProfile())
    }

    private companion object {
        const val KEY = "user_profile"
    }
}
