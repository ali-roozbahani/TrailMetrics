package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.data.di.activityHistoryModule
import dev.roozbahani.trailmetrics.data.di.commonModule
import dev.roozbahani.trailmetrics.data.di.commonTrackingModule
import dev.roozbahani.trailmetrics.data.di.databaseModule
import dev.roozbahani.trailmetrics.data.di.directionsModule
import dev.roozbahani.trailmetrics.data.di.networkModule
import dev.roozbahani.trailmetrics.data.di.useCaseModule
import dev.roozbahani.trailmetrics.data.di.userProfileModule
import org.koin.core.KoinApplication
import org.koin.core.context.startKoin
import org.koin.core.module.Module
import org.koin.dsl.KoinAppDeclaration

expect val platformModules: List<Module>

fun initKoin(appDeclaration: KoinAppDeclaration = {}): KoinApplication {
    return startKoin {
        appDeclaration()
        modules(
            commonModule,
            commonTrackingModule,
            databaseModule,
            networkModule,
            useCaseModule,
            userProfileModule,
            activityHistoryModule,
            directionsModule,
            *platformModules.toTypedArray()
        )
    }
}
