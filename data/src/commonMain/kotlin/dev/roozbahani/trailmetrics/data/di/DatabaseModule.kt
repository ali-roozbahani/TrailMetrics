package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.data.local.database.getDatabaseBuilder
import dev.roozbahani.trailmetrics.data.local.database.getRoomDatabase
import org.koin.dsl.module

val databaseModule = module {
    single<TrailMetricsDatabase> { getRoomDatabase(getDatabaseBuilder()) }
    single<ActivityDao> { get<TrailMetricsDatabase>().activityDao() }
}
