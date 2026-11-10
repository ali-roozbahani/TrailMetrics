package dev.roozbahani.trailmetrics.core.testing

import dev.roozbahani.trailmetrics.domain.route.RouteDraftStore
import dev.roozbahani.trailmetrics.domain.route.StoredRouteDraft
import kotlinx.coroutines.CompletableDeferred

/**
 * In-memory [RouteDraftStore] with the store's contract: an empty draft clears. Every draft passed to [save]
 * is kept in [savedDrafts], in order; [stored] is what [load] returns.
 */
class FakeRouteDraftStore(var stored: StoredRouteDraft? = null) : RouteDraftStore {
    val savedDrafts = mutableListOf<StoredRouteDraft>()
    var clearCallCount = 0
        private set
    var loadCallCount = 0
        private set

    /** When set, [save] throws it instead of storing the draft. */
    var saveFailure: Exception? = null

    /** When set, [save] suspends until it is completed. */
    var saveGate: CompletableDeferred<Unit>? = null

    /** When set, [load] suspends until it is completed. */
    var loadGate: CompletableDeferred<Unit>? = null

    /** When set, [load] throws it. */
    var loadFailure: Exception? = null

    override suspend fun save(draft: StoredRouteDraft) {
        saveGate?.await()
        saveFailure?.let { throw it }
        savedDrafts += draft
        stored = if (draft.isEmpty) null else draft
    }

    override suspend fun load(): StoredRouteDraft? {
        loadCallCount++
        loadGate?.await()
        loadFailure?.let { throw it }
        return stored
    }

    override suspend fun clear() {
        clearCallCount++
        stored = null
    }
}
