package dev.roozbahani.trailmetrics

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.navigation.AppRoute
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.feature.route.RouteState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private const val TAG = "SavedSessionOffer"

/** The session that survived process death as the Tracking route that shows it; null when none or consumed. */
data class SavedSessionOfferState(val offer: AppRoute.Tracking? = null)

sealed interface SavedSessionOfferAction {
    /** The nav host navigated to the offer or found the back stack already on the Tracking screen. */
    data object OfferConsumed : SavedSessionOfferAction
}

sealed interface SavedSessionOfferEvent {
    /** The stored session could not be read: nothing is offered, and it stays stored for the next start. */
    data object RestoreFailed : SavedSessionOfferEvent
}

/**
 * Restores the stored tracking session once, when the app starts, and offers a [TrackingState.Paused] or
 * [TrackingState.Finished] one with a recorded path as a navigation target. The offer stays in [state] until
 * [SavedSessionOfferAction.OfferConsumed], so a recreated Activity or a recomposition does not lose it and
 * the ViewModel never offers it a second time.
 */
class SavedSessionOfferViewModel(
    private val trackingSessionManager: TrackingSessionManager,
    private val logger: Logger
) : ViewModel() {

    private val _state = MutableStateFlow(SavedSessionOfferState())
    val state: StateFlow<SavedSessionOfferState> = _state.asStateFlow()

    private val _events = Channel<SavedSessionOfferEvent>(Channel.BUFFERED)
    val events: Flow<SavedSessionOfferEvent> = _events.receiveAsFlow()

    init {
        viewModelScope.launch {
            try {
                _state.value = SavedSessionOfferState(offerFor(trackingSessionManager.restore()))
            } catch (e: CancellationException) {
                throw e
            } catch (expected: Exception) {
                logger.debug(TAG, "Restoring the stored session failed: $expected")
                _events.send(SavedSessionOfferEvent.RestoreFailed)
            }
        }
    }

    fun onAction(action: SavedSessionOfferAction) {
        when (action) {
            SavedSessionOfferAction.OfferConsumed -> _state.update { SavedSessionOfferState() }
        }
    }

    private fun offerFor(restored: TrackingState): AppRoute.Tracking? {
        val metrics = when (restored) {
            is TrackingState.Paused -> restored.metrics
            is TrackingState.Finished -> restored.metrics
            TrackingState.Idle, is TrackingState.Tracking -> return null
        }
        val startPoint = metrics.path.firstOrNull() ?: return null
        return AppRoute.Tracking(
            startPoint = startPoint,
            plannedRoutePoints = emptyList(),
            // A session stored before the type was saved has none: the route screen's own default.
            selectedActivityType = trackingSessionManager.sessionDetails.value?.activityType
                ?: RouteState().selectedActivityType
        )
    }
}
