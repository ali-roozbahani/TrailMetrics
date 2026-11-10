package dev.roozbahani.trailmetrics.domain.route

import dev.roozbahani.trailmetrics.domain.util.Logger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/**
 * Keeps the route being planned in [store] for both platforms' route screens: [restore] reads it once,
 * [save] and [clear] write it.
 *
 * Writes run in [scope] (off the caller's thread) one at a time, latest wins: a request made while a
 * write runs replaces the request still waiting, so at most one write runs and at most one waits; no
 * queue. A clear is a request like a save, so a save requested before it never lands after it. A
 * failing write is logged and dropped: planning goes on, and the next request writes the whole draft.
 *
 * One instance for the app (one stored draft, one writer); [scope] lives as long as the app.
 */
class RouteDraftSaver(
    private val store: RouteDraftStore,
    private val logger: Logger,
    scope: CoroutineScope
) {
    // The newest request not yet started. StateFlow's collector is conflated: while a write runs,
    // newer requests replace each other and only the last is collected. The sequence number keeps two
    // equal requests in a row from being merged into one.
    private val requests = MutableStateFlow<Request?>(null)

    init {
        scope.launch {
            requests.collect { request -> request?.let { write(it.write) } }
        }
    }

    /** Stores [draft] (an empty draft clears the store, see [RouteDraftStore.save]). Returns at once. */
    fun save(draft: StoredRouteDraft) = submit(Write.Save(draft))

    /** Removes the stored draft. Returns at once. */
    fun clear() = submit(Write.Clear)

    /**
     * The stored draft, or null when there is none or it cannot be read. A failed read is logged and the
     * stored row is kept (a later save replaces it); planning starts empty.
     */
    @Throws(CancellationException::class)
    suspend fun restore(): StoredRouteDraft? =
        try {
            store.load()
        } catch (e: CancellationException) {
            throw e
        } catch (expected: Exception) {
            logger.debug(TAG, "Reading the stored route draft failed: $expected")
            null
        }

    private fun submit(write: Write) {
        requests.update { Request((it?.sequence ?: 0L) + 1, write) }
    }

    private suspend fun write(write: Write) {
        try {
            when (write) {
                is Write.Save -> store.save(write.draft)
                Write.Clear -> store.clear()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (expected: Exception) {
            logger.debug(TAG, "Writing the route draft failed: $expected")
        }
    }

    private data class Request(val sequence: Long, val write: Write)

    private sealed interface Write {
        data class Save(val draft: StoredRouteDraft) : Write
        data object Clear : Write
    }

    private companion object {
        const val TAG = "RouteDraftSaver"
    }
}
