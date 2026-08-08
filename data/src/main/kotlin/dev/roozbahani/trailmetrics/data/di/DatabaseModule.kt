package dev.roozbahani.trailmetrics.data.di

import androidx.room.Room
import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val databaseModule = module {
    single<TrailMetricsDatabase> {
        Room.databaseBuilder(
            androidContext(),
            TrailMetricsDatabase::class.java,
            "trailmetrics.db"
        ).build()
    }

    single<ActivityDao> { get<TrailMetricsDatabase>().activityDao() }
}
