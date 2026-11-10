package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.local.dao.RouteDraftDao
import dev.roozbahani.trailmetrics.data.local.repository.RouteDraftStoreImpl
import dev.roozbahani.trailmetrics.domain.route.RouteDraftStore
import org.koin.dsl.module

val routeDraftModule = module {
    single<RouteDraftStore> { RouteDraftStoreImpl(routeDraftDao = get<RouteDraftDao>()) }
}
