package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import android.content.SharedPreferences
import dev.roozbahani.trailmetrics.data.common.AndroidSnapshotFileDeleter
import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.koin.android.ext.koin.androidContext
import org.koin.core.qualifier.named
import org.koin.dsl.module

/**
 * Qualifier of the [CoroutineScope] of one `TrackingService` run. A `factory`, not a `single`: the service cancels
 * its scope in `onDestroy`, and the next run of the service needs a live one.
 */
val trackingServiceScopeQualifier = named("trackingServiceScope")

/**
 * The scope the app gives one run of `TrackingService`; the qualifier above binds it. It runs on the main thread, the
 * thread the service's `onDestroy` runs on, so a `notify()` is never in flight while the service is torn down. On a
 * worker thread (`Dispatchers.Default`, as it was) the notification for the last state landed after `onDestroy` had
 * cancelled it and stayed: the manager ends a session at the route's end and stops the service at once.
 */
fun newTrackingServiceScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

val androidCommonModule = module {
    single<SharedPreferences> {
        androidContext().getSharedPreferences("trailmetrics_prefs", Context.MODE_PRIVATE)
    }
    single<KeyValueStorage> { KeyValueStorage(sharedPreferences = get<SharedPreferences>()) }
    factory<CoroutineScope>(trackingServiceScopeQualifier) { newTrackingServiceScope() }
    single<SnapshotFileDeleter> {
        AndroidSnapshotFileDeleter(ioDispatcher = get<CoroutineDispatcher>(ioDispatcherQualifier))
    }
}
