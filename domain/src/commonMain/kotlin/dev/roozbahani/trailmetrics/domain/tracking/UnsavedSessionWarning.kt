package dev.roozbahani.trailmetrics.domain.tracking

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The warning that a save of the in-progress session failed, so the recording may be lost if the process dies
 * (owner decision of 2026-11-25). [TrackingSessionManager] raises it at most once per session; a screen shows it
 * and calls [markShown]. State and not a one-shot event, so it waits while no screen collects (tracking with the
 * screen off). It belongs to its session: every path that ends the session clears it ([endSession]), so no later
 * screen shows it for a session that is over.
 */
class UnsavedSessionWarning internal constructor() {
    private val _isRaised = MutableStateFlow(false)

    /** True from the first failed save of the current session until a screen has shown it or the session ended. */
    val isRaised: StateFlow<Boolean> = _isRaised.asStateFlow()

    // Whether this session may no longer raise the warning (it already did, or it ended); reset by [startSession].
    private val hasWarnedThisSession = MutableStateFlow(false)

    /** A screen has shown the warning: it is not raised again for this session. */
    fun markShown() {
        _isRaised.value = false
    }

    /** A save failed: raises the warning unless this session already raised it. */
    internal fun onSaveFailed() {
        if (hasWarnedThisSession.compareAndSet(expect = false, update = true)) {
            _isRaised.value = true
        }
    }

    /**
     * The session ended (stopped, discarded, or cleared once saved): the warning is cleared and later failed saves
     * raise nothing until [startSession].
     */
    internal fun endSession() {
        hasWarnedThisSession.value = true
        _isRaised.value = false
    }

    /** A new session starts: a warning of the previous one that no screen showed is dropped. */
    internal fun startSession() {
        hasWarnedThisSession.value = false
        _isRaised.value = false
    }
}
