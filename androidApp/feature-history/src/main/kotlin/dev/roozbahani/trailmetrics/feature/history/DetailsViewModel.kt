package dev.roozbahani.trailmetrics.feature.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.feature.history.util.deleteSnapshotFile
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class DetailsViewModel(
    private val activityId: Long,
    private val activityHistoryRepository: ActivityHistoryRepository
) : ViewModel() {

    private val _state = MutableStateFlow(DetailsState())
    val state: StateFlow<DetailsState> = _state.asStateFlow()

    private val _events = Channel<DetailsEvent>(Channel.BUFFERED)
    val events: Flow<DetailsEvent> = _events.receiveAsFlow()

    /**
     * Set synchronously before the delete is launched, so a second confirmation (a double tap)
     * can't delete again or send a second Deleted. Cleared if the delete throws.
     */
    private var isDeleteStarted = false

    init {
        viewModelScope.launch {
            val activity = activityHistoryRepository.getActivity(activityId)
            _state.update { it.copy(activity = activity, isLoading = false) }
        }
    }

    fun onAction(action: DetailsAction) {
        when (action) {
            DetailsAction.DeleteConfirmed -> deleteActivity()
        }
    }

    private fun deleteActivity() {
        if (isDeleteStarted) return
        isDeleteStarted = true
        viewModelScope.launch {
            runCatching {
                activityHistoryRepository.deleteActivity(activityId)
            }.onFailure {
                // Let the user retry; the failure itself still propagates.
                isDeleteStarted = false
            }.getOrThrow()
            deleteSnapshotFile(_state.value.activity?.snapshotFilePath)
            _events.send(DetailsEvent.Deleted)
        }
    }
}

data class DetailsState(
    val activity: ActivityRecord? = null,
    val isLoading: Boolean = true
)

sealed interface DetailsAction {
    data object DeleteConfirmed : DetailsAction
}

sealed interface DetailsEvent {
    data object Deleted : DetailsEvent
    data class ShowError(val error: RouteUiError) : DetailsEvent
}
