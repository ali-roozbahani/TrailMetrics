package dev.roozbahani.trailmetrics.feature.history

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.SnackbarHostState
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals

/**
 * The `Scaffold`'s insets reach the list as its content padding, so the list itself spans the whole
 * screen and scrolls under the bars. The bottom bar stands for a system bar: its height is the inset.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w411dp-h891dp")
class HistoryScreenInsetsTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun `the list spans the screen under the bottom bar`() {
        composeRule.setContent {
            TrailMetricsTheme {
                HistoryScreen(
                    state = HistoryState(activities = (1L..3L).map { activityRecord(it) }),
                    onAction = {},
                    snackBarHostState = SnackbarHostState(),
                    bottomBar = { Box(Modifier.fillMaxWidth().height(BAR_HEIGHT)) }
                )
            }
        }
        composeRule.waitForIdle()

        val screen = composeRule.onRoot().fetchSemanticsNode().boundsInRoot
        val list = composeRule.onNode(hasScrollAction()).fetchSemanticsNode().boundsInRoot

        assertEquals(screen.bottom, list.bottom, "the list ends at the screen's bottom edge, under the bar")
    }

    private companion object {
        val BAR_HEIGHT = 80.dp
    }
}
