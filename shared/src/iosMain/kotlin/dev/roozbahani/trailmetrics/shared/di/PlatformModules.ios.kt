package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.data.di.iosCommonModule
import dev.roozbahani.trailmetrics.data.di.iosLocationModule
import org.koin.core.module.Module

actual val platformModules: List<Module> = listOf(
    iosCommonModule,
    iosLocationModule
)
