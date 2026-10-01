package dev.roozbahani.trailmetrics.data.local.repository

import androidx.room3.Room
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.data.local.database.getRoomDatabase

class ActivityHistoryRepositoryImplIosTest : ActivityHistoryRepositoryImplTest() {

    override fun createDatabase(): TrailMetricsDatabase =
        getRoomDatabase(Room.inMemoryDatabaseBuilder<TrailMetricsDatabase>())
}
