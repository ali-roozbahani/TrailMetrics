package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.local.dao.RouteDraftDao
import dev.roozbahani.trailmetrics.data.local.repository.RouteDraftStoreImpl
import dev.roozbahani.trailmetrics.domain.route.RouteDraftKeeper
import dev.roozbahani.trailmetrics.domain.route.RouteDraftSaver
import dev.roozbahani.trailmetrics.domain.route.RouteDraftStore
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.koin.core.qualifier.named
import org.koin.dsl.module

private val ROUTE_DRAFT_SCOPE = named("routeDraftScope")

val routeDraftModule = module {
    // The draft's writes outlive any one route screen: the scope lives as long as the app.
    single<CoroutineScope>(ROUTE_DRAFT_SCOPE) {
        CoroutineScope(SupervisorJob() + Dispatchers.Default)
    }

    single<RouteDraftStore> { RouteDraftStoreImpl(routeDraftDao = get<RouteDraftDao>()) }

    single {
        RouteDraftSaver(
            store = get<RouteDraftStore>(),
            logger = get<Logger>(),
            scope = get<CoroutineScope>(ROUTE_DRAFT_SCOPE)
        )
    }

    // One per route screen: it holds whether that screen's plan is kept.
    factory { RouteDraftKeeper(saver = get<RouteDraftSaver>()) }
}
