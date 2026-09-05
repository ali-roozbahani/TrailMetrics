package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import android.content.SharedPreferences
import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import org.koin.android.ext.koin.androidContext
import org.koin.dsl.module

val androidCommonModule = module {
    single<SharedPreferences> {
        androidContext().getSharedPreferences("trailmetrics_prefs", Context.MODE_PRIVATE)
    }
    single<KeyValueStorage> { KeyValueStorage(sharedPreferences = get<SharedPreferences>()) }
}
