package dev.roozbahani.trailmetrics.data.di

import android.content.Context
import dev.roozbahani.trailmetrics.data.tracking.AndroidTrackingServiceLauncher
import dev.roozbahani.trailmetrics.data.tracking.OffMainLazy
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import kotlinx.coroutines.CoroutineDispatcher
import org.koin.dsl.module

val androidTrackingModule = module {
    single<TrackingServiceLauncher> {
        AndroidTrackingServiceLauncher(get<Context>())
    }

    // Does not build the manager: the service takes it from here, off the main thread (its class comment).
    single<OffMainLazy<TrackingSessionManager>> {
        OffMainLazy(
            value = inject<TrackingSessionManager>(),
            ioDispatcher = get<CoroutineDispatcher>(ioDispatcherQualifier)
        )
    }
}
