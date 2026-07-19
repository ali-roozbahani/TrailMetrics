package dev.roozbahani.trailmetrics

import android.app.Application
import dev.roozbahani.trailmetrics.data.di.commonModule
import dev.roozbahani.trailmetrics.data.di.directionsModule
import dev.roozbahani.trailmetrics.data.di.locationModule
import dev.roozbahani.trailmetrics.data.di.networkModule
import dev.roozbahani.trailmetrics.data.di.trackingModule
import dev.roozbahani.trailmetrics.data.di.useCaseModule
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
                networkModule,
                locationModule,
                directionsModule,
                useCaseModule,
                routeModule,
                trackingModule,
                trackingUiModule
            )
        }
    }
}
