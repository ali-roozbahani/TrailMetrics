package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import android.content.SharedPreferences
import dev.roozbahani.trailmetrics.data.common.AndroidSnapshotFileDeleter
import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.coroutines.CoroutineDispatcher
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val androidCommonModule = module {
    single<SharedPreferences> {
        androidContext().getSharedPreferences("trailmetrics_prefs", Context.MODE_PRIVATE)
    }
    single<KeyValueStorage> { KeyValueStorage(sharedPreferences = get<SharedPreferences>()) }
    single<SnapshotFileDeleter> {
        AndroidSnapshotFileDeleter(ioDispatcher = get<CoroutineDispatcher>(ioDispatcherQualifier))
    }
}
