package dev.roozbahani.trailmetrics

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.navigation.compose.rememberNavController
import dev.roozbahani.trailmetrics.navigation.TrailMetricsBottomBar
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** [TrailMetricsBottomBar] applies the `modifier` it is given to its root (`tm-android`, "Compose"). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class BottomBarModifierTest {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun `the bar applies the modifier it is given to its root`() {
        // The tag is set by this test on the modifier it passes in; production code has no testTag.
        rule.setContent {
            TrailMetricsBottomBar(
                navController = rememberNavController(),
                modifier = Modifier.testTag(BAR_TAG)
            )
        }

        rule.onNodeWithTag(BAR_TAG).assertIsDisplayed()
    }

    private companion object {
        const val BAR_TAG = "bottom_bar_under_test"
    }
}
