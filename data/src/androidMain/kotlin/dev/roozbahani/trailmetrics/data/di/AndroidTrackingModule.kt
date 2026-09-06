package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import dev.roozbahani.trailmetrics.data.tracking.AndroidTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import org.koin.dsl.module

val androidTrackingModule = module {
    single<TrackingServiceLauncher> {
        AndroidTrackingServiceLauncher(get<Context>())
    }
}
