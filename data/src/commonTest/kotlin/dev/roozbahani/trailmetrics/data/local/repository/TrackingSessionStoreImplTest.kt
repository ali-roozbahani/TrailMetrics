package dev.roozbahani.trailmetrics.data.local.repository

import androidx.room3.useReaderConnection
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Shared store suite. Each platform subclass supplies the database: Android host tests use the
 * platform SQLite through Robolectric, iOS uses the app's bundled driver.
 */
abstract class TrackingSessionStoreImplTest {

    protected abstract fun createDatabase(): TrailMetricsDatabase

    private lateinit var database: TrailMetricsDatabase
    private lateinit var store: TrackingSessionStoreImpl

    private val clock = object : Clock {
        override fun nowMillis(): Long = SAVED_AT
        override fun elapsedRealtimeMillis(): Long = 0L
    }

    private val a = Coordinates(51.336, 12.388)
    private val b = Coordinates(51.337, 12.389)
    private val c = Coordinates(51.338, 12.390)
    private val d = Coordinates(51.339, 12.391)

    @BeforeTest
    fun setup() {
        database = createDatabase()
        store = TrackingSessionStoreImpl(database.trackingSessionDao(), clock)
    }

    @AfterTest
    fun teardown() {
        database.close()
    }

    @Test
    fun `load returns null when nothing is stored`() = runTest {
        assertNull(store.load())
    }

    @Test
    fun `save then load returns the same metrics for each state kind`() = runTest {
        val metrics = metrics(a, b, c)

        listOf(
            TrackingState.Tracking(metrics),
            TrackingState.Paused(metrics),
            TrackingState.Finished(metrics),
        ).forEach { state ->
            store.save(state)
            assertEquals(state, store.load())
        }
    }

    @Test
    fun `a null speed comes back null`() = runTest {
        val state = TrackingState.Tracking(metrics(a).copy(currentSpeedMetersPerSecond = null))

        store.save(state)

        assertEquals(state, store.load())
    }

    @Test
    fun `saving again with more points inserts only the new ones and keeps the order`() = runTest {
        store.save(TrackingState.Tracking(metrics(a, b)))
        val rowIdsBefore = pointRowIds()

        store.save(TrackingState.Tracking(metrics(a, b, c, d)))

        val rowIdsAfter = pointRowIds()
        assertEquals(rowIdsBefore, rowIdsAfter.take(2), "the stored points were rewritten")
        assertEquals(4, rowIdsAfter.size)
        assertEquals(listOf(a, b, c, d), (store.load() as TrackingState.Tracking).metrics.path)
    }

    @Test
    fun `saving the same path again changes no points`() = runTest {
        store.save(TrackingState.Tracking(metrics(a, b)))
        val rowIdsBefore = pointRowIds()

        store.save(TrackingState.Paused(metrics(a, b)))

        assertEquals(rowIdsBefore, pointRowIds())
        assertEquals(TrackingState.Paused(metrics(a, b)), store.load())
    }

    @Test
    fun `a new session with a shorter path replaces the stored points`() = runTest {
        store.save(TrackingState.Finished(metrics(a, b, c)))

        store.save(TrackingState.Tracking(metrics(d)))

        assertEquals(TrackingState.Tracking(metrics(d)), store.load())
    }

    @Test
    fun `a new session with a longer path from another start replaces the stored points`() = runTest {
        store.save(TrackingState.Finished(metrics(a, b)))

        store.save(TrackingState.Tracking(metrics(d, c, b, a)))

        assertEquals(TrackingState.Tracking(metrics(d, c, b, a)), store.load())
    }

    @Test
    fun `save records the saved-at wall clock time`() = runTest {
        store.save(TrackingState.Tracking(metrics(a)))

        assertEquals(SAVED_AT, database.trackingSessionDao().getSession()?.savedAtEpochMillis)
    }

    @Test
    fun `Idle is not saved`() = runTest {
        store.save(TrackingState.Idle)

        assertNull(store.load())
        assertNull(database.trackingSessionDao().getSession())
    }

    @Test
    fun `clear empties both tables`() = runTest {
        store.save(TrackingState.Tracking(metrics(a, b, c)))

        store.clear()

        assertNull(store.load())
        assertNull(database.trackingSessionDao().getSession())
        assertEquals(0, database.trackingSessionDao().countPoints())
    }

    @Test
    fun `clear with nothing stored does nothing`() = runTest {
        store.clear()

        assertNull(store.load())
    }

    private fun metrics(vararg path: Coordinates) = TrackingMetrics(
        elapsedMillis = 12_345L,
        lastUpdateElapsedRealtimeMillis = 99_000L,
        distanceMeters = 321.5,
        path = path.toList(),
        currentSpeedMetersPerSecond = 2.5f
    )

    // The rowids of the stored points in sequence order: a rewritten point gets a new rowid.
    private suspend fun pointRowIds(): List<Long> =
        database.useReaderConnection { connection ->
            connection.usePrepared("SELECT rowid FROM tbl_tracking_session_points ORDER BY sequence") { statement ->
                buildList { while (statement.step()) add(statement.getLong(0)) }
            }
        }

    private companion object {
        const val SAVED_AT = 1_700_000_000_000L
    }
}
