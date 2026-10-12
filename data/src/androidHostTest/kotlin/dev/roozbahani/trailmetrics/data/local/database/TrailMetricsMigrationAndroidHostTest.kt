package dev.roozbahani.trailmetrics.data.local.database

import android.content.Context
import androidx.room3.Room
import androidx.sqlite.SQLiteDriver
import androidx.sqlite.driver.AndroidSQLiteDriver
import androidx.test.core.app.ApplicationProvider
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.nio.file.Files

// The app's BundledSQLiteDriver has no native library for the host JVM, so the host run opens the
// file through the app's pipeline (buildRoomDatabase: migrations, query context) with the platform
// SQLite that Robolectric provides. The bundled driver is covered by the iOS run.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TrailMetricsMigrationAndroidHostTest : TrailMetricsMigrationTest() {

    override val fixtureDriver: SQLiteDriver = AndroidSQLiteDriver()

    override fun createDatabaseDirectory(): String =
        Files.createTempDirectory("trailmetrics-migration").toFile().absolutePath

    override fun openWithAppPipeline(path: String): TrailMetricsDatabase =
        buildRoomDatabase(
            Room.databaseBuilder<TrailMetricsDatabase>(
                ApplicationProvider.getApplicationContext<Context>(),
                path
            ),
            AndroidSQLiteDriver()
        )

    override fun deleteDatabaseDirectory(directory: String) {
        File(directory).deleteRecursively()
    }
}
