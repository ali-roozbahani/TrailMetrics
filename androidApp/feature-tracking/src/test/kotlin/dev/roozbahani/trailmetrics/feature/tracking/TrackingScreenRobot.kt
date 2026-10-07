package dev.roozbahani.trailmetrics.feature.tracking

import androidx.activity.ComponentActivity
import androidx.annotation.StringRes
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates

/**
 * Drives the real [TrackingRoot] (ViewModel from Koin) and reads what it shows. By default the
 * map is not rendered ([LocalInspectionMode]); with `inspectionMode = false` maps-compose runs
 * over whatever `MapView` the test class provides (see `ShadowMapView`).
 */
class TrackingScreenRobot(private val rule: AndroidComposeTestRule<*, ComponentActivity>) {

    /** With [viaNavHostEntry], through the `TrackingScreen` overload the app's NavHost calls, not [TrackingRoot]. */
    fun setContent(
        startPoint: Coordinates,
        plannedRoutePoints: List<Coordinates>,
        onNavigateBack: () -> Unit,
        inspectionMode: Boolean = true,
        viaNavHostEntry: Boolean = false
    ) = apply {
        rule.setContent {
            TrailMetricsTheme {
                CompositionLocalProvider(LocalInspectionMode provides inspectionMode) {
                    if (viaNavHostEntry) {
                        TrackingScreen(
                            initialStartPoint = startPoint,
                            plannedRoutePoints = plannedRoutePoints,
                            activityType = ActivityType.Running,
                            onNavigateBack = onNavigateBack
                        )
                    } else {
                        TrackingRoot(
                            initialStartPoint = startPoint,
                            plannedRoutePoints = plannedRoutePoints,
                            activityType = ActivityType.Running,
                            onNavigateBack = onNavigateBack
                        )
                    }
                }
            }
        }
    }

    fun clickStart() = apply { button(R.string.btn_tracking_start).performClick() }

    fun clickPause() = apply { button(R.string.btn_tracking_pause).performClick() }

    fun clickResume() = apply { button(R.string.btn_tracking_resume).performClick() }

    fun clickStop() = apply { button(R.string.btn_tracking_stop).performClick() }

    fun clickFinish() = apply { button(R.string.btn_tracking_finish).performClick() }

    /** Two taps with no move in between, so the second lands before any recomposition can react to the first. */
    fun doubleTapFinish() = apply {
        button(R.string.btn_tracking_finish).performTouchInput {
            down(center)
            up()
            down(center)
            up()
        }
    }

    /** The top-left icon button. */
    fun clickBackButton() = apply {
        rule.onNodeWithContentDescription(string(R.string.cd_navigate_back)).performClick()
    }

    /** The system back gesture or key. */
    fun pressSystemBack() = apply {
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
    }

    fun confirmExit() = apply { dialogButton(R.string.dialog_exit_tracking_confirm).performClick() }

    fun dismissExit() = apply { dialogButton(R.string.dialog_exit_tracking_dismiss).performClick() }

    fun waitForIdle() = apply { rule.waitForIdle() }

    fun assertIdleControls() = apply {
        assertButtons(shown = listOf(R.string.btn_tracking_start))
    }

    fun assertTrackingControls() = apply {
        assertButtons(shown = listOf(R.string.btn_tracking_pause, R.string.btn_tracking_stop))
    }

    fun assertPausedControls() = apply {
        assertButtons(shown = listOf(R.string.btn_tracking_resume, R.string.btn_tracking_stop))
    }

    /** The completed card: its message and Finish, and none of the session controls. */
    fun assertCompletedCard() = apply {
        rule.onNodeWithText(string(R.string.msg_route_completed)).assertExists()
        assertButtons(shown = listOf(R.string.btn_tracking_finish))
    }

    fun assertCompletedCardNotShown() = apply {
        rule.onNodeWithText(string(R.string.msg_route_completed)).assertDoesNotExist()
        button(R.string.btn_tracking_finish).assertDoesNotExist()
    }

    /** Each metric's label and its value, as `MetricsDisplay` shows them. */
    fun assertMetricsShown(distance: String, time: String, speed: String, calories: String) = apply {
        listOf(
            CoreStrings.label_distance to distance,
            CoreStrings.label_time to time,
            CoreStrings.label_speed to speed,
            CoreStrings.label_calories to calories
        ).forEach { (label, value) ->
            rule.onNodeWithText(string(label)).assertExists()
            rule.onNodeWithText(value).assertExists()
        }
    }

    fun assertMetricsNotShown() = apply {
        rule.onNodeWithText(string(CoreStrings.label_distance)).assertDoesNotExist()
        rule.onNodeWithText(string(CoreStrings.label_calories)).assertDoesNotExist()
    }

    fun assertExitDialogShown() = apply {
        rule.onNode(isDialog()).assertExists()
        rule.onNodeWithText(string(R.string.dialog_exit_tracking_title)).assertExists()
        rule.onNodeWithText(string(R.string.dialog_exit_tracking_message)).assertExists()
    }

    fun assertExitDialogNotShown() = apply {
        rule.onNode(isDialog()).assertDoesNotExist()
        rule.onNodeWithText(string(R.string.dialog_exit_tracking_title)).assertDoesNotExist()
    }

    fun assertMessageShown(@StringRes message: Int) = apply {
        rule.onNodeWithText(string(message)).assertExists()
    }

    fun assertMessageNotShown(@StringRes message: Int) = apply {
        rule.onNodeWithText(string(message)).assertDoesNotExist()
    }

    /** Lets the shown snackbar's short duration (4 s) and its exit pass on the test clock. */
    fun waitForSnackbarToHide() = apply {
        rule.mainClock.advanceTimeBy(SNACKBAR_SHORT_MILLIS)
        rule.waitForIdle()
    }

    private fun assertButtons(shown: List<Int>) {
        CONTROL_BUTTONS.forEach { label ->
            if (label in shown) button(label).assertExists() else button(label).assertDoesNotExist()
        }
    }

    /** A screen button by its label; the exit dialog's confirm button has the same text as Stop. */
    private fun button(@StringRes label: Int): SemanticsNodeInteraction =
        rule.onNode(hasText(string(label)) and hasClickAction() and !hasAnyAncestor(isDialog()))

    private fun dialogButton(@StringRes label: Int): SemanticsNodeInteraction =
        rule.onNode(hasText(string(label)) and hasClickAction() and hasAnyAncestor(isDialog()))

    private fun string(@StringRes id: Int): String = rule.activity.getString(id)

    private companion object {
        /** `SnackbarDuration.Short` without accessibility services, plus a margin. */
        const val SNACKBAR_SHORT_MILLIS = 5_000L

        val CONTROL_BUTTONS = listOf(
            R.string.btn_tracking_start,
            R.string.btn_tracking_pause,
            R.string.btn_tracking_resume,
            R.string.btn_tracking_stop,
            R.string.btn_tracking_finish
        )
    }
}

private typealias CoreStrings = dev.roozbahani.trailmetrics.core.ui.R.string
