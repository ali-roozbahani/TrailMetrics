package dev.roozbahani.trailmetrics.data.local.repository

import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.data.local.entity.RouteDraftEntity
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.route.StoredRouteDraft
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/**
 * Shared store suite. Each platform subclass supplies the database: Android host tests use the
 * platform SQLite through Robolectric, iOS uses the app's bundled driver.
 */
abstract class RouteDraftStoreImplTest {

    protected abstract fun createDatabase(): TrailMetricsDatabase

    private lateinit var database: TrailMetricsDatabase
    private lateinit var store: RouteDraftStoreImpl

    @BeforeTest
    fun setup() {
        database = createDatabase()
        store = RouteDraftStoreImpl(database.routeDraftDao())
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
    fun `a full draft comes back unchanged for every activity type`() = runTest {
        ActivityType.entries.forEach { type ->
            val draft = fullDraft.copy(activityType = type)

            store.save(draft)

            assertEquals(draft, store.load())
        }
    }

    @Test
    fun `a draft without a generated route comes back without one`() = runTest {
        val draft = fullDraft.copy(generatedRoute = null)

        store.save(draft)

        assertEquals(draft, store.load())
    }

    @Test
    fun `a draft with waypoints and no start point comes back without one`() = runTest {
        val draft = fullDraft.copy(startPoint = null, generatedRoute = null)

        store.save(draft)

        assertEquals(draft, store.load())
    }

    @Test
    fun `a draft with only a start point is stored`() = runTest {
        val draft = StoredRouteDraft(START, emptyList(), null, ActivityType.Walking)

        store.save(draft)

        assertEquals(draft, store.load())
    }

    @Test
    fun `a generated route with no points comes back as an empty route and not as no route`() = runTest {
        val draft = fullDraft.copy(generatedRoute = Route(points = emptyList(), distanceMeters = 0.0))

        store.save(draft)

        assertEquals(draft, store.load())
    }

    @Test
    fun `saving again replaces the stored draft`() = runTest {
        store.save(fullDraft)
        val shorter = StoredRouteDraft(START, listOf(RoutePoint(B, 0)), null, ActivityType.Cycling)

        store.save(shorter)

        assertEquals(shorter, store.load())
    }

    @Test
    fun `an empty draft is not stored and clears the stored one`() = runTest {
        store.save(fullDraft)

        store.save(StoredRouteDraft(null, emptyList(), null, ActivityType.Running))

        assertNull(store.load())
        assertNull(database.routeDraftDao().get())
    }

    @Test
    fun `clear removes the stored draft`() = runTest {
        store.save(fullDraft)

        store.clear()

        assertNull(store.load())
        assertNull(database.routeDraftDao().get())
    }

    @Test
    fun `clear with nothing stored does nothing`() = runTest {
        store.clear()

        assertNull(store.load())
    }

    @Test
    fun `a stored route without a distance fails the load and stays stored`() = runTest {
        val row = RouteDraftEntity(
            startLatitude = START.latitude,
            startLongitude = START.longitude,
            waypoints = listOf(A),
            generatedRoutePoints = listOf(START, A, START),
            generatedRouteDistanceMeters = null,
            activityType = ActivityType.Running
        )
        database.routeDraftDao().upsert(row)

        assertFailsWith<IllegalStateException> { store.load() }
        assertEquals(row, database.routeDraftDao().get())
    }

    private val fullDraft = StoredRouteDraft(
        startPoint = START,
        waypoints = listOf(RoutePoint(A, 0), RoutePoint(B, 1), RoutePoint(C, 2)),
        generatedRoute = Route(
            points = listOf(START, A, B, C, START).mapIndexed { index, point -> RoutePoint(point, index) },
            distanceMeters = 1234.5
        ),
        activityType = ActivityType.Running
    )

    private companion object {
        val START = Coordinates(51.336, 12.388)
        val A = Coordinates(51.337, 12.389)
        val B = Coordinates(51.338, 12.390)
        val C = Coordinates(51.339, 12.391)
    }
}
