package dev.roozbahani.trailmetrics.feature.history

import androidx.activity.ComponentActivity
import androidx.annotation.StringRes
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.util.formatCalories
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import dev.roozbahani.trailmetrics.domain.util.formatElapsedTime
import dev.roozbahani.trailmetrics.domain.util.formatSpeed

/** Drives the real [DetailsRoot] (ViewModel from Koin) and reads what it shows. */
class DetailsScreenRobot(private val rule: AndroidComposeTestRule<*, ComponentActivity>) {

    fun setContent(activityId: Long, onNavigateBack: () -> Unit = {}) = apply {
        rule.setContent {
            // maps-compose's GoogleMap draws an empty Box in inspection mode, so no Maps SDK runs here.
            CompositionLocalProvider(LocalInspectionMode provides true) {
                TrailMetricsTheme {
                    DetailsRoot(activityId = activityId, onNavigateBack = onNavigateBack)
                }
            }
        }
    }

    fun clickBack() = apply {
        rule.onNodeWithContentDescription(string(R.string.cd_navigate_back)).performClick()
    }

    fun clickDelete() = apply {
        rule.onNodeWithContentDescription(string(R.string.cd_delete_activity)).performClick()
    }

    fun confirmDelete() = apply {
        rule.onNodeWithText(string(R.string.dialog_delete_activity_confirm)).performClick()
    }

    /**
     * Two real taps on the dialog's confirm button, both delivered before the next frame (as when
     * taps queue up on a busy main thread). The injector advances the main clock by the time
     * between events, and `click()` adds a move that takes time, so `click(); click()` lets the
     * first tap's recomposition close the dialog and the second tap hits nothing. Bare
     * down/up pairs at the same event time keep both taps in one frame.
     */
    fun confirmDeleteTwice() = apply {
        rule.onNodeWithText(string(R.string.dialog_delete_activity_confirm)).performTouchInput {
            down(center)
            up()
            down(center)
            up()
        }
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

    fun assertActivityShown(activity: ActivityRecord) = apply {
        rule.onNodeWithText(formatDistance(activity.distanceMeters)).assertExists()
        rule.onNodeWithText(formatElapsedTime(activity.durationMillis)).assertExists()
        rule.onNodeWithText(formatSpeed(activity.averageSpeedMetersPerSecond)).assertExists()
        rule.onNodeWithText(formatCalories(activity.calories)).assertExists()
    }

    fun assertNotFoundShown() = apply {
        rule.onNodeWithText(string(R.string.msg_activity_not_found)).assertExists()
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

    /** Exactly one error message on screen: a second one waits for the first to be dismissed. */
    fun assertOneErrorShown() = apply {
        rule.onAllNodesWithText(string(CoreStrings.msg_general_error)).assertCountEquals(1)
    }

    fun assertErrorNotShown() = apply {
        rule.onNodeWithText(string(CoreStrings.msg_general_error)).assertDoesNotExist()
    }

    /** Lets the shown snackbar's short duration (4 s) and its exit pass on the test clock. */
    fun waitForSnackbarToHide() = apply {
        rule.mainClock.advanceTimeBy(SNACKBAR_SHORT_MILLIS)
        rule.waitForIdle()
    }

    fun waitForIdle() = apply { rule.waitForIdle() }

    private fun string(@StringRes id: Int): String = rule.activity.getString(id)

    private companion object {
        /** `SnackbarDuration.Short` without accessibility services, plus a margin. */
        const val SNACKBAR_SHORT_MILLIS = 5_000L
    }
}
