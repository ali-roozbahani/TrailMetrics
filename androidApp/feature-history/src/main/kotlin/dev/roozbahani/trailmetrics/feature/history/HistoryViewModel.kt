package dev.roozbahani.trailmetrics.feature.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

class HistoryViewModel(
    activityHistoryRepository: ActivityHistoryRepository
) : ViewModel() {

    val uiState: StateFlow<HistoryUiState> = activityHistoryRepository.observeActivities()
        .map { activities -> HistoryUiState(activities, false) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000L),
            initialValue = HistoryUiState(isLoading = true)
        )
}

data class HistoryUiState(
    val activities: List<ActivityRecord> = emptyList(),
    val isLoading: Boolean = false
) {
    val isEmpty: Boolean
        get() = activities.isEmpty() && !isLoading
}
