package dev.roozbahani.trailmetrics.feature.history

import androidx.activity.ComponentActivity
import androidx.annotation.StringRes
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.util.formatCalories
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import dev.roozbahani.trailmetrics.domain.util.formatElapsedTime
import java.text.DateFormat
import java.util.Date

/**
 * Drives the real [HistoryRoot] (ViewModel from Koin) and reads what it shows. The delete
 * button is found by its content description, so a test that deletes shows a single row.
 */
class HistoryScreenRobot(private val rule: AndroidComposeTestRule<*, ComponentActivity>) {

    fun setContent(onActivityClicked: (Long) -> Unit = {}) = apply {
        rule.setContent {
            TrailMetricsTheme {
                HistoryRoot(onActivityClicked = onActivityClicked)
            }
        }
    }

    /** Clicks the row through its type label, which sits on the row's card. */
    fun clickRow(@StringRes typeLabel: Int) = apply {
        rule.onNodeWithText(string(typeLabel)).performClick()
    }

    fun clickDelete() = apply {
        rule.onNodeWithContentDescription(string(R.string.cd_delete_activity)).performClick()
    }

    fun confirmDelete() = apply {
        rule.onNodeWithText(string(R.string.dialog_delete_activity_confirm)).performClick()
    }

    fun cancelDelete() = apply {
        rule.onNodeWithText(string(R.string.dialog_delete_activity_dismiss)).performClick()
    }

    fun assertLoading() = apply {
        rule.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).assertExists()
    }

    fun assertNotLoading() = apply {
        rule.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).assertDoesNotExist()
    }

    fun assertEmptyStateShown() = apply {
        rule.onNodeWithText(string(R.string.msg_no_activities)).assertExists()
    }

    fun assertEmptyStateNotShown() = apply {
        rule.onNodeWithText(string(R.string.msg_no_activities)).assertDoesNotExist()
    }

    /** One row (its card merges its texts) shows the type label, start time and metrics. */
    fun assertRowShown(activity: ActivityRecord, @StringRes typeLabel: Int) = apply {
        rule.onNode(
            hasText(string(typeLabel)) and
                hasText(startedAt(activity)) and
                hasText(formatDistance(activity.distanceMeters)) and
                hasText(formatElapsedTime(activity.durationMillis)) and
                hasText(formatCalories(activity.calories))
        ).assertExists()
    }

    fun assertRowNotShown(activity: ActivityRecord) = apply {
        rule.onNodeWithText(startedAt(activity)).assertDoesNotExist()
    }

    fun assertDialogShown() = apply {
        rule.onNodeWithText(string(R.string.dialog_delete_activity_title)).assertExists()
    }

    fun assertDialogClosed() = apply {
        rule.onNodeWithText(string(R.string.dialog_delete_activity_title)).assertDoesNotExist()
    }

    fun assertErrorShown() = apply {
        rule.onNodeWithText(string(CoreStrings.msg_general_error)).assertExists()
    }

    private fun startedAt(activity: ActivityRecord): String =
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(activity.startedAtEpochMillis))

    private fun string(@StringRes id: Int): String = rule.activity.getString(id)
}
