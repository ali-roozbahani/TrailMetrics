package dev.roozbahani.trailmetrics

import android.app.Application
import dev.roozbahani.trailmetrics.data.di.directionsModule
import dev.roozbahani.trailmetrics.data.di.locationModule
import dev.roozbahani.trailmetrics.data.di.networkModule
import org.koin.android.ext.koin.androidContext
import org.koin.core.context.startKoin

class TrailMetricsApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidContext(this@TrailMetricsApplication)
            modules(
                networkModule,
                locationModule,
                directionsModule
            )
        }
    }
}
