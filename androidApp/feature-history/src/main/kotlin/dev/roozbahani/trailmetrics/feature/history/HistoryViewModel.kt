package dev.roozbahani.trailmetrics.feature.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.usecase.ObserveActivitiesUseCase
import dev.roozbahani.trailmetrics.feature.history.util.deleteSnapshotFile
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class HistoryViewModel(
    private val activityHistoryRepository: ActivityHistoryRepository,
    private val observeActivitiesUseCase: ObserveActivitiesUseCase
) : ViewModel() {

    val state: StateFlow<HistoryState> = activityHistoryRepository.observeActivities()
        .map { activities -> HistoryState(activities, false) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000L),
            initialValue = HistoryState(isLoading = true)
        )

    private val _events = Channel<HistoryEvent>(Channel.BUFFERED)
    val events: Flow<HistoryEvent> = _events.receiveAsFlow()

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
            activityHistoryRepository.deleteActivity(activity.id)
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
