package dev.roozbahani.trailmetrics.data.local.repository

import android.content.Context
import androidx.room3.Room
import androidx.sqlite.driver.AndroidSQLiteDriver
import androidx.test.core.app.ApplicationProvider
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// The app's BundledSQLiteDriver has no native library for the host JVM, so the host run uses
// the platform SQLite that Robolectric provides. The bundled driver is covered by the iOS run.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ActivityHistoryRepositoryImplAndroidHostTest : ActivityHistoryRepositoryImplTest() {

    override fun createDatabase(): TrailMetricsDatabase =
        Room.inMemoryDatabaseBuilder<TrailMetricsDatabase>(
            ApplicationProvider.getApplicationContext<Context>()
        )
            .setDriver(AndroidSQLiteDriver())
            .build()
}
