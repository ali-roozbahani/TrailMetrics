package dev.roozbahani.trailmetrics.feature.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.domain.model.ActivitiesUpdate
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.usecase.ObserveActivitiesUseCase
import dev.roozbahani.trailmetrics.feature.history.util.deleteSnapshotFile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.runningFold
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class HistoryViewModel(
    private val activityHistoryRepository: ActivityHistoryRepository,
    private val observeActivitiesUseCase: ObserveActivitiesUseCase
) : ViewModel() {

    private val _events = Channel<HistoryEvent>(Channel.BUFFERED)
    val events: Flow<HistoryEvent> = _events.receiveAsFlow()

    /**
     * Built on [ObserveActivitiesUseCase], not the repository's flow, so a failing read can't
     * crash the app: it stops loading, keeps the list this collection last read and shows an
     * error. The use case's flow completes after a failure; a new collection (after the stop
     * timeout) reads again.
     */
    val state: StateFlow<HistoryState> = observeActivitiesUseCase()
        .runningFold(HistoryState(isLoading = true)) { current, update ->
            when (update) {
                is ActivitiesUpdate.Loaded -> HistoryState(update.activities, isLoading = false)
                ActivitiesUpdate.Failed -> {
                    _events.send(HistoryEvent.ShowError(RouteUiError.General))
                    current.copy(isLoading = false)
                }
            }
        }
        // runningFold emits its seed first; stateIn's initial value already stands for it.
        .drop(1)
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000L),
            initialValue = HistoryState(isLoading = true)
        )

    fun onAction(action: HistoryAction) {
        when (action) {
            is HistoryAction.ActivityClicked -> openDetails(action.activityId)
            is HistoryAction.DeleteConfirmed -> deleteActivity(action.activity)
        }
    }

    private fun openDetails(activityId: Long) {
        viewModelScope.launch {
            _events.send(HistoryEvent.NavigateToDetails(activityId))
        }
    }

    private fun deleteActivity(activity: ActivityRecord) {
        viewModelScope.launch {
            try {
                activityHistoryRepository.deleteActivity(activity.id)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Keep the snapshot file; the record is still in the list.
                _events.send(HistoryEvent.ShowError(RouteUiError.General))
                return@launch
            }
            deleteSnapshotFile(activity.snapshotFilePath)
        }
    }
}

data class HistoryState(
    val activities: List<ActivityRecord> = emptyList(),
    val isLoading: Boolean = false
) {
    val isEmpty: Boolean
        get() = activities.isEmpty() && !isLoading
}

sealed interface HistoryAction {
    data class ActivityClicked(val activityId: Long) : HistoryAction
    data class DeleteConfirmed(val activity: ActivityRecord) : HistoryAction
}

sealed interface HistoryEvent {
    data class NavigateToDetails(val activityId: Long) : HistoryEvent
    data class ShowError(val error: RouteUiError) : HistoryEvent
}
