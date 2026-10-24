package dev.roozbahani.trailmetrics.data.local.database

import androidx.sqlite.SQLiteDriver
import dev.roozbahani.trailmetrics.data.local.entity.ActivityEntity
import dev.roozbahani.trailmetrics.data.local.repository.TrackingSessionStoreImpl
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.Clock
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Migration harness. Each case writes a database file at an old version outside Room (a
 * [FrozenDatabaseVersion]), opens it through the app's builder pipeline and migration list
 * ([appMigrations]), and asserts every field of every row at the current version.
 *
 * Each platform subclass supplies the drivers and the file location: Android host tests use the
 * platform SQLite through Robolectric (the app's bundled driver has no host library), iOS uses
 * the app's bundled driver through the app's own `getRoomDatabase`.
 *
 * A migration M to N adds the fixture of version M to [frozenDatabaseVersions] if it is missing,
 * and one case named for `MIGRATION_M_N` that opens that fixture and asserts every row,
 * including the values the migration gives the new or changed columns.
 */
abstract class TrailMetricsMigrationTest {

    /** Writes the frozen fixtures: the platform's plain SQLite, without Room. */
    protected abstract val fixtureDriver: SQLiteDriver

    /** Creates an empty directory for this test's database file and returns its path. */
    protected abstract fun createDatabaseDirectory(): String

    /** Opens the database at [path] through the app's builder pipeline and migration list. */
    protected abstract fun openWithAppPipeline(path: String): TrailMetricsDatabase

    /** Removes the directory from [createDatabaseDirectory] with everything in it. */
    protected abstract fun deleteDatabaseDirectory(directory: String)

    private lateinit var directory: String
    private lateinit var databasePath: String

    @BeforeTest
    fun createDirectory() {
        directory = createDatabaseDirectory()
        databasePath = "$directory/$DATABASE_FILE_NAME"
    }

    @AfterTest
    fun deleteDirectory() {
        deleteDatabaseDirectory(directory)
    }

    @Test
    fun `the app's migrations lead from version 1 to the current version without a gap`() {
        val reached = appMigrations.sortedBy { it.startVersion }.fold(1) { version, migration ->
            assertEquals(version, migration.startVersion, "no migration starts at version $version")
            migration.endVersion
        }
        assertEquals(CURRENT_DATABASE_VERSION, reached)
    }

    @Test
    fun `MIGRATION_1_2 keeps every row and stores user_version 2`() = runTest {
        val rows = openAndReadAll(databaseVersion1)

        assertEquals(version1RowsAtCurrentVersion, rows)
        assertEquals(CURRENT_DATABASE_VERSION, storedUserVersion())
    }

    @Test
    fun `MIGRATION_1_2 adds the empty session tables the store can write and read`() = runTest {
        databaseVersion1.writeTo(fixtureDriver, databasePath)
        val database = openWithAppPipeline(databasePath)
        try {
            val dao = database.trackingSessionDao()
            assertNull(dao.getSession())
            assertEquals(0, dao.countPoints())

            val state = TrackingState.Paused(
                TrackingMetrics(
                    elapsedMillis = 5_000,
                    lastUpdateElapsedRealtimeMillis = 7_000,
                    distanceMeters = 12.5,
                    path = listOf(Coordinates(1.0, 2.0), Coordinates(3.0, 4.0)),
                    currentSpeedMetersPerSecond = null
                )
            )
            val store = TrackingSessionStoreImpl(dao, FixedClock)
            store.save(state)
            assertEquals(state, store.load())
        } finally {
            database.close()
        }
    }

    /**
     * Writes [fixture] to the file, opens it through the app's pipeline (which runs the app's
     * migrations), and returns every row through the DAO, newest first, each also read by id.
     */
    private suspend fun openAndReadAll(fixture: FrozenDatabaseVersion): List<ActivityEntity> {
        fixture.writeTo(fixtureDriver, databasePath)
        val database = openWithAppPipeline(databasePath)
        try {
            val dao = database.activityDao()
            val rows = dao.observeAll().first()
            rows.forEach { assertEquals(it, dao.getById(it.id)) }
            return rows
        } finally {
            database.close()
        }
    }

    private object FixedClock : Clock {
        override fun nowMillis(): Long = 1_700_300_000_000
        override fun elapsedRealtimeMillis(): Long = 0L
    }

    private fun storedUserVersion(): Int {
        val connection = fixtureDriver.open(databasePath)
        try {
            val statement = connection.prepare("PRAGMA user_version")
            try {
                statement.step()
                return statement.getInt(0)
            } finally {
                statement.close()
            }
        } finally {
            connection.close()
        }
    }

    // The rows of databaseVersion1 as the app reads them at the current version, newest first.
    private val version1RowsAtCurrentVersion = listOf(
        ActivityEntity(
            id = 7,
            activityType = ActivityType.Walking,
            startedAtEpochMillis = 1_700_200_000_000,
            endedAtEpochMillis = 1_700_200_900_000,
            distanceMeters = 1100.25,
            durationMillis = 900_000,
            averageSpeedMetersPerSecond = 1.25f,
            calories = null,
            plannedRoutePoints = listOf(Coordinates(48.1374, 11.5755)),
            actualPath = emptyList(),
            snapshotFilePath = "/snapshots/activity-7.png",
        ),
        ActivityEntity(
            id = 2,
            activityType = ActivityType.Cycling,
            startedAtEpochMillis = 1_700_100_000_000,
            endedAtEpochMillis = 1_700_103_600_000,
            distanceMeters = 30250.0,
            durationMillis = 3_600_000,
            averageSpeedMetersPerSecond = null,
            calories = null,
            plannedRoutePoints = emptyList(),
            actualPath = listOf(Coordinates(-33.8688, 151.2093), Coordinates(-33.87, 151.21)),
            snapshotFilePath = null,
        ),
        ActivityEntity(
            id = 1,
            activityType = ActivityType.Running,
            startedAtEpochMillis = 1_700_000_000_000,
            endedAtEpochMillis = 1_700_001_800_000,
            distanceMeters = 5012.5,
            durationMillis = 1_800_000,
            averageSpeedMetersPerSecond = 2.75f,
            calories = 412.5,
            plannedRoutePoints = listOf(Coordinates(51.336, 12.388), Coordinates(51.337, 12.389)),
            actualPath = listOf(
                Coordinates(51.336, 12.388),
                Coordinates(51.3365, 12.3885),
                Coordinates(51.337, 12.389),
            ),
            snapshotFilePath = "/snapshots/activity-1.png",
        ),
    )
}
