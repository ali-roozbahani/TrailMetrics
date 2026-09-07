package dev.roozbahani.trailmetrics

import android.app.Application
import dev.roozbahani.trailmetrics.feature.history.di.historyUiModule
import dev.roozbahani.trailmetrics.feature.route.di.routeModule
import dev.roozbahani.trailmetrics.feature.tracking.di.trackingUiModule
import dev.roozbahani.trailmetrics.shared.di.initKoin
import org.koin.android.ext.koin.androidContext

class TrailMetricsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        initKoin {
            androidContext(this@TrailMetricsApplication)
            modules(routeModule, trackingUiModule, historyUiModule)
        }
    }
}
