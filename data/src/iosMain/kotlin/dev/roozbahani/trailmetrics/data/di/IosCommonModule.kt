package dev.roozbahani.trailmetrics.data.di

import dev.roozbahani.trailmetrics.data.common.IosSnapshotFileDeleter
import dev.roozbahani.trailmetrics.data.common.KeyValueStorage
import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.coroutines.CoroutineDispatcher
import org.koin.dsl.module

val iosCommonModule = module {
    single<KeyValueStorage> { KeyValueStorage() }
    single<SnapshotFileDeleter> {
        IosSnapshotFileDeleter(ioDispatcher = get<CoroutineDispatcher>(ioDispatcherQualifier))
    }
}
