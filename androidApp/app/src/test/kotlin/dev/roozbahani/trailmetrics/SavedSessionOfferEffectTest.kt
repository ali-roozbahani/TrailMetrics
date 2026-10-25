package dev.roozbahani.trailmetrics

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import dev.roozbahani.trailmetrics.core.navigation.AppRoute
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.navigation.CoordinatesNavType
import dev.roozbahani.trailmetrics.navigation.PlannedRoutePointsNavType
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.reflect.typeOf
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * [SavedSessionOfferEffect] on a real NavHost with stub destinations: the nav host's real destinations are
 * Maps screens, which this test does not need. The effect is the code that decides about the navigation.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class SavedSessionOfferEffectTest {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private lateinit var navController: NavHostController
    private val offer = mutableStateOf<AppRoute.Tracking?>(null)
    private val stopTrackingRequested = mutableStateOf(false)
    private var consumed = 0

    private fun setContent(startDestination: Any) {
        rule.setContent {
            navController = rememberNavController()
            TestNavHost(navController, startDestination, offer, stopTrackingRequested) {
                consumed++
                offer.value = null
            }
        }
        rule.waitForIdle()
    }

    private fun trackingEntries(): Int =
        navController.currentBackStack.value.count { it.destination.hasRoute<AppRoute.Tracking>() }

    private fun isOnTracking(): Boolean = navController.currentDestination?.hasRoute<AppRoute.Tracking>() == true

    @Test
    fun `the offer navigates to the Tracking screen once and is consumed`() {
        setContent(AppRoute.RoutePlanning)

        offer.value = OFFER
        rule.waitForIdle()

        assertTrue(isOnTracking())
        assertEquals(1, trackingEntries())
        assertEquals(1, consumed)
        assertNull(offer.value)
    }

    @Test
    fun `a recomposition after the navigation does not navigate again`() {
        setContent(AppRoute.RoutePlanning)
        offer.value = OFFER
        rule.waitForIdle()

        stopTrackingRequested.value = false
        stopTrackingRequested.value = true
        stopTrackingRequested.value = false
        rule.waitForIdle()

        assertEquals(1, trackingEntries())
        assertEquals(1, consumed)
    }

    @Test
    fun `the offer is consumed without navigating when the back stack is already on the Tracking screen`() {
        setContent(OFFER)

        offer.value = OFFER
        rule.waitForIdle()

        assertTrue(isOnTracking())
        assertEquals(1, trackingEntries())
        assertEquals(1, consumed)
        assertNull(offer.value)
    }

    @Test
    fun `an offer present at the first composition is handled after the NavHost`() {
        offer.value = OFFER

        setContent(AppRoute.RoutePlanning)

        assertTrue(isOnTracking())
        assertEquals(1, trackingEntries())
        assertEquals(1, consumed)
    }

    @Test
    fun `the offer is consumed without navigating when the notification Stop discards the session`() {
        setContent(AppRoute.RoutePlanning)
        stopTrackingRequested.value = true

        offer.value = OFFER
        rule.waitForIdle()

        assertEquals(0, trackingEntries())
        assertEquals(1, consumed)
    }

    private companion object {
        val OFFER = AppRoute.Tracking(Coordinates(47.0, 8.0), emptyList(), ActivityType.Cycling)
    }
}

@Composable
private fun TestNavHost(
    navController: NavHostController,
    startDestination: Any,
    offer: MutableState<AppRoute.Tracking?>,
    stopTrackingRequested: MutableState<Boolean>,
    onConsumed: () -> Unit
) {
    NavHost(navController = navController, startDestination = startDestination) {
        composable<AppRoute.RoutePlanning> { Text("route") }
        composable<AppRoute.Tracking>(
            typeMap = mapOf(
                typeOf<Coordinates>() to CoordinatesNavType,
                typeOf<List<Coordinates>>() to PlannedRoutePointsNavType,
            )
        ) { Text("tracking") }
    }
    SavedSessionOfferEffect(navController, offer.value, stopTrackingRequested, onConsumed)
}
