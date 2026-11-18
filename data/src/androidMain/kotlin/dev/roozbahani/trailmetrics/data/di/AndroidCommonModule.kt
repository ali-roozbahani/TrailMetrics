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

val androidCommonModule = module {
    single<SharedPreferences> {
        androidContext().getSharedPreferences("trailmetrics_prefs", Context.MODE_PRIVATE)
    }
    single<KeyValueStorage> { KeyValueStorage(sharedPreferences = get<SharedPreferences>()) }
    factory<CoroutineScope>(trackingServiceScopeQualifier) { CoroutineScope(SupervisorJob() + Dispatchers.Default) }
    single<SnapshotFileDeleter> {
        AndroidSnapshotFileDeleter(ioDispatcher = get<CoroutineDispatcher>(ioDispatcherQualifier))
    }
}
