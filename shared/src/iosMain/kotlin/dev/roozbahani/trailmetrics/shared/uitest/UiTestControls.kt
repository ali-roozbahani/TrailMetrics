package dev.roozbahani.trailmetrics.shared.uitest

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/**
 * What a UI test reads and drives in one launch started by [doInitKoinIosForUiTest].
 *
 * The counters are incremented by the fakes on whatever thread their coroutine runs on and read
 * from the main thread. Each one is a [MutableStateFlow] incremented with [update], an atomic
 * compare-and-set, so no increment is lost and a read always sees a whole value.
 */
class UiTestControls internal constructor(private val scenario: UiTestScenario) {
    private val directionsRequests = MutableStateFlow(0)
    private val directionsCompleted = MutableStateFlow(0)
    private val saves = MutableStateFlow(0)
    private val deletes = MutableStateFlow(0)
    private val gate = CompletableDeferred<Unit>()

    /** `getClosedRoute` calls received, counted on entry, before any hold. */
    val directionsRequestCount: Int get() = directionsRequests.value

    /** `getClosedRoute` calls that returned a route. */
    val directionsCompletedCount: Int get() = directionsCompleted.value

    /** `saveActivity` calls that completed and added an activity. */
    val saveCount: Int get() = saves.value

    /** `deleteActivity` calls that completed without failing. */
    val deleteCount: Int get() = deletes.value

    /** Completes every held call. Calls made after this are not held. */
    fun releaseHeldCalls() {
        gate.complete(Unit)
    }

    internal suspend fun awaitReleaseIfHeld(call: UiTestHeldCall) {
        if (scenario.heldCall == call) gate.await()
    }

    internal fun countDirectionsRequest() = directionsRequests.update { it + 1 }

    internal fun countDirectionsCompleted() = directionsCompleted.update { it + 1 }

    internal fun countSave() = saves.update { it + 1 }

    internal fun countDelete() = deletes.update { it + 1 }
}
