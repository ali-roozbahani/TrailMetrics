package dev.roozbahani.trailmetrics

import android.app.Application
import dev.roozbahani.trailmetrics.data.di.activityHistoryModule
import dev.roozbahani.trailmetrics.data.di.androidCommonModule
import dev.roozbahani.trailmetrics.data.di.androidLocationModule
import dev.roozbahani.trailmetrics.data.di.androidTrackingModule
import dev.roozbahani.trailmetrics.data.di.commonModule
import dev.roozbahani.trailmetrics.data.di.commonTrackingModule
import dev.roozbahani.trailmetrics.data.di.databaseModule
import dev.roozbahani.trailmetrics.data.di.directionsModule
import dev.roozbahani.trailmetrics.data.di.networkModule
import dev.roozbahani.trailmetrics.data.di.useCaseModule
import dev.roozbahani.trailmetrics.data.di.userProfileModule
import dev.roozbahani.trailmetrics.feature.history.di.historyUiModule
import dev.roozbahani.trailmetrics.feature.route.di.routeModule
import dev.roozbahani.trailmetrics.feature.tracking.di.trackingUiModule
import org.koin.android.ext.koin.androidContext
import org.koin.core.context.startKoin

class TrailMetricsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidContext(this@TrailMetricsApplication)
            modules(
                commonModule,
                androidCommonModule,
                databaseModule,
                networkModule,
                androidLocationModule,
                directionsModule,
                useCaseModule,
                routeModule,
                commonTrackingModule,
                androidTrackingModule,
                trackingUiModule,
                userProfileModule,
                activityHistoryModule,
                historyUiModule
            )
        }
    }
}
