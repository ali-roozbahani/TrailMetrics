package dev.roozbahani.trailmetrics

import android.app.Application
import dev.roozbahani.trailmetrics.data.di.ioDispatcherQualifier
import dev.roozbahani.trailmetrics.di.APPLICATION_SCOPE
import dev.roozbahani.trailmetrics.di.appModule
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.feature.history.di.historyUiModule
import dev.roozbahani.trailmetrics.feature.route.di.routeModule
import dev.roozbahani.trailmetrics.feature.tracking.di.trackingUiModule
import dev.roozbahani.trailmetrics.shared.di.initKoin
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import org.koin.android.ext.koin.androidContext

class TrailMetricsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        installDebugStrictMode(applicationInfo)
        val koin = initKoin {
            androidContext(this@TrailMetricsApplication)
            modules(appModule, routeModule, trackingUiModule, historyUiModule)
        }.koin
        // The first screens ask for these on the main thread and building them reads the disk (D9): the manager
        // builds the database, the directions repository the HTTP client (its engine and plugins are found in the jar),
        // the profile repository the preferences file.
        warmUp(
            scope = koin.get<CoroutineScope>(APPLICATION_SCOPE),
            ioDispatcher = koin.get<CoroutineDispatcher>(ioDispatcherQualifier),
            logger = koin.get<Logger>()
        ) {
            koin.get<TrackingSessionManager>()
            koin.get<DirectionsRepository>()
            koin.get<UserProfileRepository>()
        }
    }
}
