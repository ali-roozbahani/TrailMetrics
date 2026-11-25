package dev.roozbahani.trailmetrics.data.local.database

import dev.roozbahani.trailmetrics.data.local.repository.TrackingSessionStoreImpl
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import kotlinx.coroutines.test.runTest
import platform.Foundation.NSFileManager
import platform.Foundation.NSFileProtectionCompleteUntilFirstUserAuthentication
import platform.Foundation.NSFileProtectionType
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Which paths get which protection class, and when. The simulator neither stores nor reports a protection
 * class (`attributesOfItemAtPath` has no `NSFileProtectionKey` there), so the calls are recorded through the
 * [FileProtectionSetter] seam; that a locked device keeps the file writable is a device check, not a test.
 */
@OptIn(ExperimentalForeignApi::class) // createDirectoryAtPath takes an NSError pointer
class DatabaseFileProtectionIosTest {

    private val fileManager = NSFileManager.defaultManager
    private lateinit var directory: String
    private lateinit var path: String
    private val logged = mutableListOf<String>()
    private val logger = object : Logger {
        override fun debug(tag: String, message: String) {
            logged += message
        }
    }
    private val calls = mutableListOf<Pair<String, NSFileProtectionType>>()
    private val recordingSetter = FileProtectionSetter { path, protection ->
        calls += path to protection
        null
    }

    @BeforeTest
    fun setup() {
        directory = NSTemporaryDirectory().trimEnd('/') + "/trailmetrics-protection-" + NSUUID().UUIDString
        path = "$directory/$DATABASE_FILE_NAME"
        val isCreated = fileManager.createDirectoryAtPath(
            path = directory,
            withIntermediateDirectories = true,
            attributes = null,
            error = null
        )
        check(isCreated) { "could not create $directory" }
    }

    @AfterTest
    fun teardown() {
        fileManager.removeItemAtPath(directory, error = null)
    }

    @Test
    fun `opening the database through the app's builder gives its directory and files the decided class`() = runTest {
        val database = getRoomDatabase(databaseBuilderAt(path, logger, recordingSetter), Dispatchers.IO)
        try {
            store(database).save(session())
        } finally {
            database.close()
        }

        assertEquals(NSFileProtectionCompleteUntilFirstUserAuthentication, databaseFileProtection)
        assertEquals(
            listOf(directory, path, "$path-wal", "$path-shm").map { it to databaseFileProtection },
            calls
        )
        assertEquals(emptyList(), logged)
    }

    @Test
    fun `only the companion files that exist are given the class`() {
        val existing = setOf(path, "$path-journal")

        applyDatabaseFileProtection(path, recordingSetter) { it in existing }

        assertEquals(listOf(directory, path, "$path-journal"), calls.map { it.first })
    }

    @Test
    fun `a failing path is logged and the session is still saved`() = runTest {
        val failingSetter = FileProtectionSetter { path, _ -> if (path == directory) "refused" else null }
        val database = getRoomDatabase(databaseBuilderAt(path, logger, failingSetter), Dispatchers.IO)
        try {
            val store = store(database)
            store.save(session())

            assertEquals(session().state, store.load()?.state)
        } finally {
            database.close()
        }

        assertEquals(listOf("Setting the database file protection failed: $directory: refused"), logged)
    }

    @Test
    fun `the file manager setter accepts the call for an existing file`() {
        check(fileManager.createFileAtPath(path, contents = null, attributes = null))

        assertNull(fileManagerProtectionSetter.setProtection(path, databaseFileProtection))
    }

    private fun store(database: TrailMetricsDatabase) = TrackingSessionStoreImpl(
        database.trackingSessionDao(),
        database.trackingSessionPlanDao(),
        RoomWriteTransaction(database),
        clock,
        Dispatchers.IO
    )

    private val clock = object : Clock {
        override fun nowMillis(): Long = 1_000L
        override fun elapsedRealtimeMillis(): Long = 0L
    }

    private fun session() = StoredTrackingSession(
        state = TrackingState.Tracking(
            TrackingMetrics(
                elapsedMillis = 1_000L,
                lastUpdateElapsedRealtimeMillis = 1_000L,
                distanceMeters = 10.0,
                path = listOf(Coordinates(51.336, 12.388), Coordinates(51.337, 12.389))
            )
        ),
        activityType = null,
        startedAtEpochMillis = 1_000L
    )
}
