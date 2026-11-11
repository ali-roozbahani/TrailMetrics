package dev.roozbahani.trailmetrics.domain.route

import kotlinx.coroutines.flow.MutableStateFlow
import kotlin.coroutines.cancellation.CancellationException

/**
 * The route screen's side of keeping its plan across process death, one per screen, the same on both
 * platforms. Nothing is written until the plan is kept: the user changed it ([onUserChange]) or a stored
 * plan was restored ([keepRestoredPlan]). So a stored plan that is still loading, or failed to load, is not
 * replaced by the current location alone; and a user change made before the restored plan is shown wins:
 * the loaded plan is dropped, as `TrackingSessionManager.restore` never replaces newer state.
 *
 * The screen calls [onUserChange], [keepRestoredPlan] and [save] on its main thread.
 */
class RouteDraftKeeper(private val saver: RouteDraftSaver) {

    private val isPlanKept = MutableStateFlow(false)

    /**
     * The stored plan, read once when the screen is created; null when there is none, it cannot be read
     * (logged, the row kept, no error for the user: a plan is cheap to make again), or the user changed the
     * plan while it was read. The screen shows it only if [keepRestoredPlan] then returns true.
     */
    @Throws(CancellationException::class)
    suspend fun loadStoredPlan(): StoredRouteDraft? {
        val draft = saver.restore() ?: return null
        return if (isPlanKept.value) null else draft
    }

    /**
     * Called right before the screen shows the plan [loadStoredPlan] returned, in the same main-thread step:
     * true when the user has not changed the plan, which is kept from now on; false when the user changed it
     * first, and the loaded plan is dropped. Separate from the load so that nothing (a location result) can
     * save the screen's own state between keeping the plan and showing it.
     */
    fun keepRestoredPlan(): Boolean = isPlanKept.compareAndSet(expect = false, update = true)

    /** The user changes the plan or uses it up: from now on it is written, and a plan still loading is dropped. */
    fun onUserChange() {
        isPlanKept.value = true
    }

    /** Writes [draft] (off the caller's thread, latest wins) once the plan is kept; an empty draft clears. */
    fun save(draft: StoredRouteDraft) {
        if (isPlanKept.value) saver.save(draft)
    }

    /** The plan was used to start tracking: the stored one is removed. */
    fun clear() {
        saver.clear()
    }
}
