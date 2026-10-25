package dev.roozbahani.trailmetrics.data.local.repository

import androidx.room3.useReaderConnection
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
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
        assertNull(loadState())
    }

    @Test
    fun `save then load returns the same metrics for each state kind`() = runTest {
        val metrics = metrics(a, b, c)

        listOf(
            TrackingState.Tracking(metrics),
            TrackingState.Paused(metrics),
            TrackingState.Finished(metrics),
        ).forEach { state ->
            save(state)
            assertEquals(state, loadState())
        }
    }

    @Test
    fun `a null speed comes back null`() = runTest {
        val state = TrackingState.Tracking(metrics(a).copy(currentSpeedMetersPerSecond = null))

        save(state)

        assertEquals(state, loadState())
    }

    @Test
    fun `saving again with more points inserts only the new ones and keeps the order`() = runTest {
        save(TrackingState.Tracking(metrics(a, b)))
        val rowIdsBefore = pointRowIds()

        save(TrackingState.Tracking(metrics(a, b, c, d)))

        val rowIdsAfter = pointRowIds()
        assertEquals(rowIdsBefore, rowIdsAfter.take(2), "the stored points were rewritten")
        assertEquals(4, rowIdsAfter.size)
        assertEquals(listOf(a, b, c, d), (loadState() as TrackingState.Tracking).metrics.path)
    }

    @Test
    fun `saving the same path again changes no points`() = runTest {
        save(TrackingState.Tracking(metrics(a, b)))
        val rowIdsBefore = pointRowIds()

        save(TrackingState.Paused(metrics(a, b)))

        assertEquals(rowIdsBefore, pointRowIds())
        assertEquals(TrackingState.Paused(metrics(a, b)), loadState())
    }

    @Test
    fun `a new session with a shorter path replaces the stored points`() = runTest {
        save(TrackingState.Finished(metrics(a, b, c)))

        save(TrackingState.Tracking(metrics(d)))

        assertEquals(TrackingState.Tracking(metrics(d)), loadState())
    }

    @Test
    fun `a new session with a longer path from another start replaces the stored points`() = runTest {
        save(TrackingState.Finished(metrics(a, b)))

        save(TrackingState.Tracking(metrics(d, c, b, a)))

        assertEquals(TrackingState.Tracking(metrics(d, c, b, a)), loadState())
    }

    @Test
    fun `save records the saved-at wall clock time`() = runTest {
        save(TrackingState.Tracking(metrics(a)))

        assertEquals(SAVED_AT, database.trackingSessionDao().getSession()?.savedAtEpochMillis)
    }

    @Test
    fun `Idle is not saved`() = runTest {
        save(TrackingState.Idle)

        assertNull(loadState())
        assertNull(database.trackingSessionDao().getSession())
    }

    @Test
    fun `clear empties both tables`() = runTest {
        save(TrackingState.Tracking(metrics(a, b, c)))

        store.clear()

        assertNull(loadState())
        assertNull(database.trackingSessionDao().getSession())
        assertEquals(0, database.trackingSessionDao().countPoints())
    }

    @Test
    fun `clear with nothing stored does nothing`() = runTest {
        store.clear()

        assertNull(loadState())
    }

    @Test
    fun `every activity type and the start time come back with the session`() = runTest {
        ActivityType.entries.forEach { type ->
            val session = StoredTrackingSession(TrackingState.Paused(metrics(a, b)), type, STARTED_AT)
            store.save(session)

            assertEquals(session, store.load())
        }
    }

    @Test
    fun `a session saved without a type and start time loads with both null`() = runTest {
        store.save(StoredTrackingSession(TrackingState.Paused(metrics(a)), null, null))

        val loaded = checkNotNull(store.load())
        assertNull(loaded.activityType)
        assertNull(loaded.startedAtEpochMillis)
        val row = database.trackingSessionDao().getSession()
        assertNull(row?.activityType)
        assertNull(row?.startedAtEpochMillis)
    }

    @Test
    fun `saving again replaces the stored type and start time`() = runTest {
        store.save(StoredTrackingSession(TrackingState.Tracking(metrics(a)), ActivityType.Running, STARTED_AT))
        store.save(StoredTrackingSession(TrackingState.Tracking(metrics(a, b)), ActivityType.Cycling, STARTED_AT + 1))

        val loaded = checkNotNull(store.load())
        assertEquals(ActivityType.Cycling, loaded.activityType)
        assertEquals(STARTED_AT + 1, loaded.startedAtEpochMillis)
    }

    @Test
    fun `a stored type this version does not know loads as unknown`() = runTest {
        store.save(StoredTrackingSession(TrackingState.Paused(metrics(a)), ActivityType.Running, STARTED_AT))
        val dao = database.trackingSessionDao()
        dao.upsertSession(checkNotNull(dao.getSession()).copy(activityType = "Skiing"))

        val loaded = checkNotNull(store.load())

        assertEquals(TrackingState.Paused(metrics(a)), loaded.state)
        assertNull(loaded.activityType)
        assertEquals(STARTED_AT, loaded.startedAtEpochMillis)
    }

    private suspend fun save(state: TrackingState) =
        store.save(StoredTrackingSession(state, ActivityType.Running, STARTED_AT))

    private suspend fun loadState(): TrackingState? = store.load()?.state

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
        const val STARTED_AT = 1_699_999_000_000L
    }
}
