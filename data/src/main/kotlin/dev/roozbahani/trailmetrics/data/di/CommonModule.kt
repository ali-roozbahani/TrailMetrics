package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import android.content.SharedPreferences
import dev.roozbahani.trailmetrics.data.common.AndroidLogger
import dev.roozbahani.trailmetrics.data.common.SystemClock
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val commonModule = module {
    single<Clock> { SystemClock() }
    single<Logger> { AndroidLogger() }
    single<SharedPreferences> {
        androidContext().getSharedPreferences("trailmetrics_prefs", Context.MODE_PRIVATE)
    }
}
