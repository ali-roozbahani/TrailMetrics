package dev.roozbahani.trailmetrics.domain.fakes

import dev.roozbahani.trailmetrics.domain.route.RouteDraftStore
import dev.roozbahani.trailmetrics.domain.route.StoredRouteDraft
import kotlinx.coroutines.CompletableDeferred

/**
 * In-memory [RouteDraftStore] with the store's contract (an empty draft clears). [writes] records each
 * write in order: the saved draft, or null for a clear.
 */
class FakeRouteDraftStore(var stored: StoredRouteDraft? = null) : RouteDraftStore {
    val writes = mutableListOf<StoredRouteDraft?>()

    /** When set, each write suspends until it is completed. */
    var writeGate: CompletableDeferred<Unit>? = null

    /** When set, [save] throws it. */
    var saveFailure: Exception? = null

    /** When set, [load] throws it. */
    var loadFailure: Exception? = null

    override suspend fun save(draft: StoredRouteDraft) {
        writeGate?.await()
        saveFailure?.let { throw it }
        writes += draft
        stored = if (draft.isEmpty) null else draft
    }

    override suspend fun load(): StoredRouteDraft? {
        loadFailure?.let { throw it }
        return stored
    }

    override suspend fun clear() {
        writeGate?.await()
        writes += null
        stored = null
    }
}
