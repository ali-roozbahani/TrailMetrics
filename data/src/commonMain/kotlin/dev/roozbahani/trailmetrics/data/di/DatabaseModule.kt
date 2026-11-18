package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.dao.RouteDraftDao
import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionDao
import dev.roozbahani.trailmetrics.data.local.dao.TrackingSessionPlanDao
import dev.roozbahani.trailmetrics.data.local.database.RoomWriteTransaction
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.data.local.database.WriteTransaction
import dev.roozbahani.trailmetrics.data.local.database.getDatabaseBuilder
import dev.roozbahani.trailmetrics.data.local.database.getRoomDatabase
import kotlinx.coroutines.CoroutineDispatcher
import org.koin.dsl.module

val databaseModule = module {
    single<TrailMetricsDatabase> { getRoomDatabase(getDatabaseBuilder(), get<CoroutineDispatcher>(ioDispatcherQualifier)) }
    single<ActivityDao> { get<TrailMetricsDatabase>().activityDao() }
    single<TrackingSessionDao> { get<TrailMetricsDatabase>().trackingSessionDao() }
    single<TrackingSessionPlanDao> { get<TrailMetricsDatabase>().trackingSessionPlanDao() }
    single<WriteTransaction> { RoomWriteTransaction(get<TrailMetricsDatabase>()) }
    single<RouteDraftDao> { get<TrailMetricsDatabase>().routeDraftDao() }
}
