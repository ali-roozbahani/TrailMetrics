package dev.roozbahani.trailmetrics.feature.route

import androidx.activity.ComponentActivity
import androidx.annotation.StringRes
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.lifecycle.ViewModelProvider
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RoutePoint

/**
 * Drives the real [RouteRoot] (ViewModel from Koin) and reads what it shows. The map is not
 * rendered under [LocalInspectionMode], so a map long-press or a marker tap is the action the
 * map would dispatch, sent to the ViewModel the Root uses (the activity's, default key).
 */
class RouteScreenRobot(private val rule: AndroidComposeTestRule<*, ComponentActivity>) {

    private lateinit var viewModel: RouteViewModel

    fun setContent(
        onStartTrackingClicked: (Coordinates, List<Coordinates>, ActivityType) -> Unit = { _, _, _ -> }
    ) = apply {
        rule.setContent {
            TrailMetricsTheme {
                CompositionLocalProvider(LocalInspectionMode provides true) {
                    RouteRoot(onStartTrackingClicked = onStartTrackingClicked)
                }
            }
        }
        viewModel = ViewModelProvider(rule.activity)[RouteViewModel::class.java]
    }

    /** What `onMapLongClicked` dispatches. */
    fun longPressMap(vararg coordinates: Coordinates) = apply {
        coordinates.forEach { viewModel.onAction(RouteAction.MapTapped(it)) }
    }

    /** What a waypoint marker's `onClick` dispatches. */
    fun tapWaypointMarker(waypoint: RoutePoint) = apply {
        viewModel.onAction(RouteAction.WaypointRemoved(waypoint))
    }

    fun clickGenerate() = apply {
        rule.onNodeWithText(string(R.string.btn_generate_route)).performClick()
    }

    fun doubleTapGenerate() = apply {
        doubleTap(R.string.btn_generate_route)
    }

    /** The top-right icon button (its content description); the panel's button has the same text. */
    fun clickResetIcon() = apply {
        rule.onNodeWithContentDescription(string(R.string.btn_reset_route)).performClick()
    }

    /** The Start Tracking panel's Reset button (its text); the icon button has it as content description. */
    fun clickResetInPanel() = apply {
        rule.onNodeWithText(string(R.string.btn_reset_route)).performClick()
    }

    fun selectActivityType(type: ActivityType) = apply {
        rule.onNodeWithText(string(labelOf(type))).performClick()
    }

    fun clickStartTracking() = apply {
        rule.onNodeWithText(string(R.string.btn_start_tracking)).performClick()
    }

    /**
     * What the panel's Start Tracking button dispatches, sent to the ViewModel: while the error
     * snackbar is shown it may lie over the panel's bottom (see [waitForSnackbarToHide]).
     */
    fun startTrackingThroughViewModel() = apply {
        viewModel.onAction(RouteAction.StartTrackingClicked)
    }

    fun doubleTapStartTracking() = apply {
        doubleTap(R.string.btn_start_tracking)
    }

    fun enterWeight(text: String) = apply {
        rule.onNode(hasSetTextAction()).performTextReplacement(text)
    }

    /**
     * Through the button's click action: under Robolectric an injected touch does not reach a
     * ModalBottomSheet's window (checked with a bare sheet and button), while the action runs the
     * same `onClick`.
     */
    fun clickSave() = apply {
        rule.onNodeWithText(string(R.string.btn_save)).performSemanticsAction(SemanticsActions.OnClick)
    }

    fun waitForIdle() = apply {
        rule.waitForIdle()
    }

    /**
     * The snackbar lies over the Generate button and takes its taps while shown, so a test that taps
     * Generate after an error first lets the snackbar's short duration pass on the test clock.
     */
    fun waitForSnackbarToHide() = apply {
        rule.mainClock.advanceTimeBy(SNACKBAR_SHORT_MILLIS)
        rule.waitForIdle()
    }

    fun assertGenerateEnabled() = apply {
        rule.onNodeWithText(string(R.string.btn_generate_route)).assertIsEnabled()
    }

    fun assertGenerateDisabled() = apply {
        rule.onNodeWithText(string(R.string.btn_generate_route)).assertIsNotEnabled()
    }

    fun assertGenerateNotShown() = apply {
        rule.onNodeWithText(string(R.string.btn_generate_route)).assertDoesNotExist()
    }

    /** The Generate button shows its indicator instead of its label and can't be tapped. */
    fun assertGenerateLoading() = apply {
        rule.onNode(hasClickAction() and hasAnyDescendant(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)))
            .assertIsNotEnabled()
        rule.onNodeWithText(string(R.string.btn_generate_route)).assertDoesNotExist()
    }

    fun assertNotLoading() = apply {
        rule.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).assertDoesNotExist()
    }

    fun assertPanelShown() = apply {
        rule.onNodeWithText(string(R.string.btn_start_tracking)).assertExists()
        rule.onNodeWithText(string(R.string.btn_reset_route)).assertExists()
        ActivityType.entries.forEach { rule.onNodeWithText(string(labelOf(it))).assertExists() }
    }

    fun assertPanelNotShown() = apply {
        rule.onNodeWithText(string(R.string.btn_start_tracking)).assertDoesNotExist()
        rule.onNodeWithText(string(R.string.btn_reset_route)).assertDoesNotExist()
        ActivityType.entries.forEach { rule.onNodeWithText(string(labelOf(it))).assertDoesNotExist() }
    }

    fun assertActivityTypeSelected(type: ActivityType) = apply {
        rule.onNodeWithText(string(labelOf(type))).assertIsSelected()
    }

    fun assertProfileSheetShown() = apply {
        rule.onNodeWithText(string(R.string.title_user_profile)).assertExists()
    }

    fun assertProfileSheetNotShown() = apply {
        rule.onNodeWithText(string(R.string.title_user_profile)).assertDoesNotExist()
    }

    fun assertSaveEnabled() = apply {
        rule.onNodeWithText(string(R.string.btn_save)).assertIsEnabled()
    }

    fun assertSaveDisabled() = apply {
        rule.onNodeWithText(string(R.string.btn_save)).assertIsNotEnabled()
    }

    fun assertMessageShown(@StringRes message: Int) = apply {
        rule.onNodeWithText(string(message)).assertExists()
    }

    fun assertMessageNotShown(@StringRes message: Int) = apply {
        rule.onNodeWithText(string(message)).assertDoesNotExist()
    }

    /** Two taps with no move in between, so the second lands before any recomposition can remove the button. */
    private fun doubleTap(@StringRes text: Int) {
        rule.onNodeWithText(string(text)).performTouchInput {
            down(center)
            up()
            down(center)
            up()
        }
    }

    @StringRes
    private fun labelOf(type: ActivityType): Int = when (type) {
        ActivityType.Running -> CoreStrings.activity_type_running
        ActivityType.Cycling -> CoreStrings.activity_type_cycling
        ActivityType.Walking -> CoreStrings.activity_type_walking
    }

    private fun string(@StringRes id: Int): String = rule.activity.getString(id)

    private companion object {
        /** Longer than Material 3's `SnackbarDuration.Short` (4 s) plus its exit animation. */
        const val SNACKBAR_SHORT_MILLIS = 5_000L
    }
}

private typealias CoreStrings = dev.roozbahani.trailmetrics.core.ui.R.string
