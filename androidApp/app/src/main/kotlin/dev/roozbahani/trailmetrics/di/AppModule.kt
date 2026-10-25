package dev.roozbahani.trailmetrics.di

import dev.roozbahani.trailmetrics.SavedSessionOfferViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import org.koin.core.module.dsl.viewModelOf
import org.koin.core.qualifier.named
import org.koin.dsl.module

val APPLICATION_SCOPE = named("applicationScope")

val appModule = module {
    // Lives as long as the process: work that must finish although the Activity that asked for it is
    // recreated or gone (the notification's Stop).
    single<CoroutineScope>(APPLICATION_SCOPE) { CoroutineScope(SupervisorJob()) }
    viewModelOf(::SavedSessionOfferViewModel)
}
