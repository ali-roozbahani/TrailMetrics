package dev.roozbahani.trailmetrics.feature.history

import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import org.junit.Test
import kotlin.test.assertEquals

/** The derived [HistoryState.isEmpty], for every combination of list contents and loading. */
class HistoryStateTest {

    @Test
    fun `isEmpty is true only for an empty list that has finished loading`() {
        val expected = mapOf(
            HistoryState(activities = emptyList(), isLoading = false) to true,
            HistoryState(activities = emptyList(), isLoading = true) to false,
            HistoryState(activities = listOf(activityRecord(id = 1L)), isLoading = false) to false,
            HistoryState(activities = listOf(activityRecord(id = 1L)), isLoading = true) to false
        )

        expected.forEach { (state, isEmpty) ->
            assertEquals(isEmpty, state.isEmpty, "for $state")
        }
    }
}
