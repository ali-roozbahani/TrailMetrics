package dev.roozbahani.trailmetrics.data.local.database

import android.content.Context
import androidx.room3.Room
import androidx.sqlite.driver.AndroidSQLiteDriver
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.coroutines.CoroutineContext
import kotlin.test.assertTrue

/** The query context that the caller hands to the database pipeline is the one the queries run on. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BuildRoomDatabaseQueryContextTest {

    @Test
    fun `a query runs on the query context passed to the database pipeline`() {
        val queryDispatcher = CountingDispatcher()
        val database = buildRoomDatabase(
            Room.inMemoryDatabaseBuilder<TrailMetricsDatabase>(ApplicationProvider.getApplicationContext<Context>()),
            AndroidSQLiteDriver(),
            queryDispatcher
        )

        try {
            runBlocking { database.activityDao().getById(1L) }

            assertTrue(queryDispatcher.dispatched > 0, "the query was dispatched on the injected context")
        } finally {
            database.close()
        }
    }

    /** Runs what it is given on an IO thread and counts how many blocks it ran. */
    private class CountingDispatcher : CoroutineDispatcher() {
        @Volatile
        var dispatched = 0
            private set

        override fun dispatch(context: CoroutineContext, block: Runnable) {
            dispatched++
            Dispatchers.IO.dispatch(context, block)
        }
    }
}
