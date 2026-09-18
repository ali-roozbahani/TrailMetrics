package dev.roozbahani.trailmetrics.feature.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.feature.history.util.deleteSnapshotFile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class DetailsViewModel(
    private val activityId: Long,
    private val activityHistoryRepository: ActivityHistoryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(DetailsUiState())
    val uiState: StateFlow<DetailsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val activity = activityHistoryRepository.getActivity(activityId)
            _uiState.update { it.copy(activity = activity, isLoading = false) }
        }
    }

    fun onDeleteConfirmed(onDeleted: () -> Unit) {
        viewModelScope.launch {
            activityHistoryRepository.deleteActivity(activityId)
            deleteSnapshotFile(_uiState.value.activity?.snapshotFilePath)
            onDeleted()
        }
    }
}

data class DetailsUiState(
    val activity: ActivityRecord? = null,
    val isLoading: Boolean = true
)
