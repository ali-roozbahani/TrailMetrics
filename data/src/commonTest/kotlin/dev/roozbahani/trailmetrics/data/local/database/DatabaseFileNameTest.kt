package dev.roozbahani.trailmetrics.data.local.database

import kotlin.test.Test
import kotlin.test.assertEquals

class DatabaseFileNameTest {

    // Both platforms open the database file by this name. Renaming it makes every installed app
    // open a new, empty database next to the old one, so this literal must change only together
    // with a decision on how existing users keep their data.
    @Test
    fun `the database file name is pinned`() {
        assertEquals("trailmetrics.db", DATABASE_FILE_NAME)
    }
}
