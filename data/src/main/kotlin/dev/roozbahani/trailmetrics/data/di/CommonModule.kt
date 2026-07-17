package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.common.SystemClock
import dev.roozbahani.trailmetrics.domain.util.Clock
import org.koin.dsl.module

val commonModule = module {
    single<Clock> { SystemClock() }
}
