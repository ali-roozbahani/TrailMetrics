package dev.roozbahani.trailmetrics

import dev.roozbahani.trailmetrics.data.di.ioDispatcherQualifier
import dev.roozbahani.trailmetrics.di.APPLICATION_SCOPE
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.koin.core.Koin

private const val TAG = "WarmUp"

/**
 * Builds something heavy on [ioDispatcher] before the first screen asks for it on the main thread. The
 * tracking session manager is one: building it builds the Room database behind it (the database path is read
 * from disk), and the first screen's ViewModel would otherwise be the first to ask, in composition (`tm-robustness`,
 * D9). A failure is logged and the next caller builds it again where it needs it, and sees the failure there.
 */
internal fun warmUp(scope: CoroutineScope, ioDispatcher: CoroutineDispatcher, logger: Logger, build: () -> Unit): Job =
    scope.launch(ioDispatcher) {
        try {
            build()
        } catch (e: CancellationException) {
            throw e
        } catch (expected: Exception) {
            logger.debug(TAG, "Warming up failed, the first caller builds it again: $expected")
        }
    }

/**
 * The singletons the first screens ask for on the main thread, built on the I/O dispatcher right after Koin starts: the
 * manager builds the database, the directions repository the HTTP client (its engine and plugins are found in the jar),
 * the profile repository the preferences file (D9).
 */
internal fun warmUpFirstScreens(koin: Koin): Job =
    warmUp(
        scope = koin.get<CoroutineScope>(APPLICATION_SCOPE),
        ioDispatcher = koin.get<CoroutineDispatcher>(ioDispatcherQualifier),
        logger = koin.get<Logger>()
    ) {
        koin.get<TrackingSessionManager>()
        koin.get<DirectionsRepository>()
        koin.get<UserProfileRepository>()
    }
