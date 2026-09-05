package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import org.koin.dsl.module

val iosCommonModule = module {
    single<KeyValueStorage> { KeyValueStorage() }
}
