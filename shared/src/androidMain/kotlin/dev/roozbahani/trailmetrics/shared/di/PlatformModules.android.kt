package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.data.di.androidCommonModule
import dev.roozbahani.trailmetrics.data.di.androidLocationModule
import dev.roozbahani.trailmetrics.data.di.androidTrackingModule
import org.koin.core.module.Module

actual val platformModules: List<Module> = listOf(
    androidCommonModule,
    androidLocationModule,
    androidTrackingModule
)
