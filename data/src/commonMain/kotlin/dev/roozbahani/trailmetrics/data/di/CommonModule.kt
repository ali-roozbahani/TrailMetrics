package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.common.SystemClock
import dev.roozbahani.trailmetrics.data.common.createLogger
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.IO
import org.koin.core.qualifier.named
import org.koin.dsl.module

/** Qualifier of the [CoroutineDispatcher] for blocking I/O; the platform modules and others reuse it. */
val ioDispatcherQualifier = named("ioDispatcher")

val commonModule = module {
    single<Clock> { SystemClock() }
    single<Logger> { createLogger() }
    single<CoroutineDispatcher>(ioDispatcherQualifier) { Dispatchers.IO }
}
