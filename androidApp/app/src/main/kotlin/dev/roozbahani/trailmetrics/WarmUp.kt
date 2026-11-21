package dev.roozbahani.trailmetrics

import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

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
