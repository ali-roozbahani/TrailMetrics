package dev.roozbahani.trailmetrics.data.tracking

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * A lazily built value for a component that runs on the main thread, built on [ioDispatcher] when nobody has built
 * it yet. The tracking service uses it for `TrackingSessionManager`: building the manager builds the Room database
 * behind its store (the database path is read from disk), and a cold restart of the service, where the process is
 * new, is the first to ask for it. Once the value exists, [get] returns it at once, without a switch. The caller
 * names no dispatcher.
 */
class OffMainLazy<T>(
    private val value: Lazy<T>,
    private val ioDispatcher: CoroutineDispatcher
) {
    suspend fun get(): T = if (value.isInitialized()) value.value else withContext(ioDispatcher) { value.value }
}
