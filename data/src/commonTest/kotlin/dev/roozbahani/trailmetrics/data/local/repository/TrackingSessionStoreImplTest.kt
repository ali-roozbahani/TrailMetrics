@file:OptIn(ExperimentalCoroutinesApi::class) // the test dispatchers have no stable replacement

package dev.roozbahani.trailmetrics.data.local.repository

import androidx.room3.useReaderConnection
import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionDao
import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionPlanDao
import dev.roozbahani.trailmetrics.data.local.database.RoomWriteTransaction
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionEntity
import dev.roozbahani.trailmetrics.data.local.entity.TrackingSessionPlanPointEntity
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlin.coroutines.ContinuationInterceptor
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertSame
import kotlin.test.assertNotNull
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
        store = TrackingSessionStoreImpl(
            database.trackingSessionDao(),
            database.trackingSessionPlanDao(),
            RoomWriteTransaction(database),
            clock,
            UnconfinedTestDispatcher()
        )
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

    @Test
    fun `the planned route comes back in order with the session`() = runTest {
        val session = StoredTrackingSession(
            TrackingState.Paused(metrics(d)),
            ActivityType.Running,
            STARTED_AT,
            listOf(c, a, b)
        )

        store.save(session)

        assertEquals(session, store.load())
    }

    @Test
    fun `a session saved without a planned route loads with an empty one`() = runTest {
        store.save(StoredTrackingSession(TrackingState.Paused(metrics(a)), ActivityType.Running, STARTED_AT))

        assertEquals(emptyList(), checkNotNull(store.load()).plannedRoute)
    }

    @Test
    fun `a new session with another plan replaces the stored plan`() = runTest {
        store.save(
            StoredTrackingSession(
                TrackingState.Finished(metrics(a, b)),
                ActivityType.Running,
                STARTED_AT,
                listOf(a, b, c)
            )
        )

        val second = StoredTrackingSession(
            TrackingState.Tracking(metrics(d)),
            ActivityType.Cycling,
            STARTED_AT + 1,
            listOf(d, c)
        )
        store.save(second)

        assertEquals(second, store.load())
    }

    @Test
    fun `a new session with no plan drops the plan of the stored one`() = runTest {
        store.save(
            StoredTrackingSession(
                TrackingState.Finished(metrics(a, b)),
                ActivityType.Running,
                STARTED_AT,
                listOf(a, b, c)
            )
        )

        val second = StoredTrackingSession(TrackingState.Tracking(metrics(d)), ActivityType.Cycling, STARTED_AT + 1)
        store.save(second)

        assertEquals(second, store.load())
    }

    @Test
    fun `saving the same session again changes no plan points`() = runTest {
        val plan = listOf(a, b, c)
        store.save(plannedSession(TrackingState.Tracking(metrics(a)), *plan.toTypedArray()))
        val rowIdsBefore = planRowIds()

        store.save(plannedSession(TrackingState.Tracking(metrics(a, b)), *plan.toTypedArray()))

        assertEquals(3, rowIdsBefore.size)
        assertEquals(rowIdsBefore, planRowIds(), "the stored plan points were rewritten")
    }

    @Test
    fun `a store of a new process keeps the stored plan points of the same session`() = runTest {
        val plan = listOf(a, b, c)
        store.save(plannedSession(TrackingState.Tracking(metrics(a)), *plan.toTypedArray()))
        val rowIdsBefore = planRowIds()
        val restartedStore = TrackingSessionStoreImpl(
            database.trackingSessionDao(),
            database.trackingSessionPlanDao(),
            RoomWriteTransaction(database),
            clock,
            UnconfinedTestDispatcher()
        )

        restartedStore.save(plannedSession(TrackingState.Tracking(metrics(a, b)), *plan.toTypedArray()))

        assertEquals(rowIdsBefore, planRowIds(), "the stored plan points were rewritten")
    }

    @Test
    fun `a session saved again after clear gets its plan points back`() = runTest {
        val session = plannedSession(TrackingState.Tracking(metrics(a)), a, b, c)
        store.save(session)
        store.clear()

        store.save(session)

        assertEquals(session, store.load())
        assertEquals(3, database.trackingSessionPlanDao().count())
    }

    @Test
    fun `a longer plan of the same session start replaces the stored plan points`() = runTest {
        store.save(plannedSession(TrackingState.Tracking(metrics(a)), a, b))

        val longer = plannedSession(TrackingState.Tracking(metrics(a)), a, b, c, d)
        store.save(longer)

        assertEquals(longer, store.load())
    }

    @Test
    fun `a failure while the plan is inserted keeps the previous session and its plan`() = runTest {
        val first = plannedSession(TrackingState.Tracking(metrics(a, b)), a, b, c)
        store.save(first)
        val failing = TrackingSessionStoreImpl(
            database.trackingSessionDao(),
            FailingPlanInsert(database.trackingSessionPlanDao()),
            RoomWriteTransaction(database),
            clock,
            UnconfinedTestDispatcher()
        )

        assertFails { failing.save(secondSession(listOf(d, c))) }

        assertEquals(first, store.load())
    }

    @Test
    fun `a failure while the session row is saved keeps the previous plan`() = runTest {
        val first = plannedSession(TrackingState.Tracking(metrics(a, b)), a, b, c)
        store.save(first)
        val failing = TrackingSessionStoreImpl(
            FailingSessionSave(database.trackingSessionDao()),
            database.trackingSessionPlanDao(),
            RoomWriteTransaction(database),
            clock,
            UnconfinedTestDispatcher()
        )

        assertFails { failing.save(secondSession(listOf(d))) }

        assertEquals(first, store.load())
    }

    @Test
    fun `deleting the session row deletes the plan points by the foreign key and not by a query of its own`() =
        runTest {
            store.save(plannedSession(TrackingState.Tracking(metrics(a)), a, b, c))
            assertEquals(3, database.trackingSessionPlanDao().count())

            database.trackingSessionDao().deleteSession()

            assertEquals(0, database.trackingSessionPlanDao().count())
        }

    @Test
    fun `clear empties the plan table`() = runTest {
        store.save(plannedSession(TrackingState.Tracking(metrics(a)), a, b))

        store.clear()

        assertNull(store.load())
        assertEquals(0, database.trackingSessionPlanDao().count())
    }

    @Test
    fun `a plan point cannot be stored for a session that does not exist`() = runTest {
        val orphan = TrackingSessionPlanPointEntity(sessionId = 1, sequence = 0, latitude = 1.0, longitude = 2.0)

        val failure = runCatching { database.trackingSessionPlanDao().insert(listOf(orphan)) }.exceptionOrNull()

        assertNotNull(failure)
        assertEquals(0, database.trackingSessionPlanDao().count())
    }

    // Another session than the one of plannedSession: its own start time and type.
    private fun secondSession(plan: List<Coordinates>) =
        StoredTrackingSession(TrackingState.Tracking(metrics(d)), ActivityType.Cycling, STARTED_AT + 1, plan)

    private fun plannedSession(state: TrackingState, vararg plan: Coordinates) =
        StoredTrackingSession(state, ActivityType.Running, STARTED_AT, plan.toList())

    private suspend fun planRowIds(): List<Long> =
        database.useReaderConnection { connection ->
            val sql = "SELECT rowid FROM tbl_tracking_session_plan_points ORDER BY sequence"
            connection.usePrepared(sql) { statement ->
                buildList { while (statement.step()) add(statement.getLong(0)) }
            }
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

    @Test
    fun `every storage call reaches the storage on the injected dispatcher`() = runTest {
        val queue = StandardTestDispatcher(testScheduler)
        val seen = mutableListOf<Pair<String, ContinuationInterceptor?>>()
        var phase = ""
        val queued = TrackingSessionStoreImpl(
            RecordsInterceptor(database.trackingSessionDao(), seen) { phase },
            database.trackingSessionPlanDao(),
            RoomWriteTransaction(database),
            clock,
            queue
        )
        val session = StoredTrackingSession(TrackingState.Tracking(metrics(a, b)), ActivityType.Running, STARTED_AT)
        val caller = UnconfinedTestDispatcher(testScheduler)

        phase = "save"
        val saving = backgroundScope.async(caller) { queued.save(session) }
        testScheduler.runCurrent()
        saving.await()
        phase = "load"
        val loading = backgroundScope.async(caller) { queued.load() }
        testScheduler.runCurrent()
        assertNotNull(loading.await())
        phase = "clear"
        val clearing = backgroundScope.async(caller) { queued.clear() }
        testScheduler.runCurrent()
        clearing.await()

        // A save reads the stored plan before its transaction, and the transaction runs on Room's own context.
        assertEquals(setOf("save", "load", "clear"), seen.map { it.first }.toSet())
        seen.forEach { (call, interceptor) -> assertSame(queue, interceptor, "$call ran on another dispatcher") }
    }

    // The rowids of the stored points in sequence order: a rewritten point gets a new rowid.
    private suspend fun pointRowIds(): List<Long> =
        database.useReaderConnection { connection ->
            connection.usePrepared("SELECT rowid FROM tbl_tracking_session_points ORDER BY sequence") { statement ->
                buildList { while (statement.step()) add(statement.getLong(0)) }
            }
        }

    // Throws on the plan insert, the last write of a save, after the old plan was deleted.
    private class FailingPlanInsert(
        private val delegate: TrackingSessionPlanDao
    ) : TrackingSessionPlanDao by delegate {
        override suspend fun insert(points: List<TrackingSessionPlanPointEntity>) {
            error("the plan insert failed")
        }
    }

    // Throws on the session row, after the old plan was deleted.
    private class FailingSessionSave(private val delegate: TrackingSessionDao) : TrackingSessionDao by delegate {
        override suspend fun save(session: TrackingSessionEntity, path: List<Coordinates>) {
            error("the session save failed")
        }
    }

    // Records the dispatcher that a read or clear of the session DAO arrives on, before Room's own switch (a
    // save's write goes through Room's transaction, which runs on its own context, so it is not recorded).
    private class RecordsInterceptor(
        private val delegate: TrackingSessionDao,
        private val seen: MutableList<Pair<String, ContinuationInterceptor?>>,
        private val phase: () -> String
    ) : TrackingSessionDao by delegate {
        override suspend fun getSession(): TrackingSessionEntity? {
            seen += phase() to currentCoroutineContext()[ContinuationInterceptor]
            return delegate.getSession()
        }

        override suspend fun clear() {
            seen += phase() to currentCoroutineContext()[ContinuationInterceptor]
            delegate.clear()
        }
    }

    private companion object {
        const val SAVED_AT = 1_700_000_000_000L
        const val STARTED_AT = 1_699_999_000_000L
    }
}
