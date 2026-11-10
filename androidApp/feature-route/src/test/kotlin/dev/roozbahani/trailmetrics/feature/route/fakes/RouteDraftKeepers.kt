package dev.roozbahani.trailmetrics.feature.route.fakes

import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeRouteDraftStore
import dev.roozbahani.trailmetrics.domain.route.RouteDraftKeeper
import dev.roozbahani.trailmetrics.domain.route.RouteDraftSaver
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher

/** The real keeper and saver over [store], writing at once on [scheduler] (an unconfined dispatcher). */
@OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
fun inMemoryRouteDraftKeeper(
    scheduler: TestCoroutineScheduler,
    store: FakeRouteDraftStore = FakeRouteDraftStore(),
    logger: FakeLogger = FakeLogger()
): RouteDraftKeeper = RouteDraftKeeper(RouteDraftSaver(store, logger, TestScope(UnconfinedTestDispatcher(scheduler))))
