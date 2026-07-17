package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.common.AndroidLogger
import dev.roozbahani.trailmetrics.data.common.SystemClock
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import org.koin.dsl.module

val commonModule = module {
    single<Clock> { SystemClock() }
    single<Logger> { AndroidLogger() }
}
