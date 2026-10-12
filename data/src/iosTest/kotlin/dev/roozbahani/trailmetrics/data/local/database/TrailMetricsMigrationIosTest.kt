package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.Room
import androidx.sqlite.SQLiteDriver
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSFileManager
import platform.Foundation.NSTemporaryDirectory
import platform.Foundation.NSUUID

// Opens the file through the app's own getRoomDatabase, so the run uses the app's bundled driver.
@OptIn(ExperimentalForeignApi::class)
class TrailMetricsMigrationIosTest : TrailMetricsMigrationTest() {

    override val fixtureDriver: SQLiteDriver = BundledSQLiteDriver()

    override fun createDatabaseDirectory(): String {
        val directory = NSTemporaryDirectory().trimEnd('/') + "/trailmetrics-migration-" + NSUUID().UUIDString
        val isCreated = NSFileManager.defaultManager.createDirectoryAtPath(
            path = directory,
            withIntermediateDirectories = true,
            attributes = null,
            error = null
        )
        check(isCreated) { "could not create $directory" }
        return directory
    }

    override fun openWithAppPipeline(path: String): TrailMetricsDatabase =
        getRoomDatabase(Room.databaseBuilder<TrailMetricsDatabase>(name = path))

    override fun deleteDatabaseDirectory(directory: String) {
        NSFileManager.defaultManager.removeItemAtPath(directory, error = null)
    }
}
