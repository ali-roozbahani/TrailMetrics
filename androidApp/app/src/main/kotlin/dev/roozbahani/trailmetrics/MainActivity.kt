package dev.roozbahani.trailmetrics

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.core.navigation.AppRoute
import dev.roozbahani.trailmetrics.data.tracking.TrackingService
import dev.roozbahani.trailmetrics.di.APPLICATION_SCOPE
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.feature.history.DetailsScreen
import dev.roozbahani.trailmetrics.feature.history.HistoryScreen
import dev.roozbahani.trailmetrics.feature.route.RouteScreen
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreen
import dev.roozbahani.trailmetrics.navigation.CoordinatesNavType
import dev.roozbahani.trailmetrics.navigation.PlannedRoutePointsNavType
import dev.roozbahani.trailmetrics.navigation.TrailMetricsBottomBar
import kotlin.reflect.typeOf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import org.koin.android.ext.android.inject
import org.koin.androidx.compose.koinViewModel

private const val TAG = "MainActivity"

class MainActivity : ComponentActivity() {

    private val trackingSessionManager: TrackingSessionManager by inject()

    private val applicationScope: CoroutineScope by inject(APPLICATION_SCOPE)

    private val logger: Logger by inject()

    // Set when the tracking notification's Stop action launches/resumes this Activity —
    // read once by TrailMetricsNavHost to pop back to Route, matching what tapping Stop
    // inside TrackingScreen already does.
    private val stopTrackingRequested: MutableState<Boolean> = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A recreated Activity (rotation) still holds the intent of the first launch: Stop is not replayed.
        if (savedInstanceState == null) handleStopTrackingIntent(intent)
        setContent {
            TrailMetricsTheme {
                TrailMetricsRoot(stopTrackingRequested = stopTrackingRequested)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleStopTrackingIntent(intent)
    }

    // Discarding the session doesn't need Compose, so it starts immediately here rather than being
    // deferred into the LaunchedEffect below. It runs in the application scope, not in the Activity's:
    // the Activity may be recreated or gone before the stored session is cleared. Only the resulting
    // navigation (which needs the NavHostController) is deferred into Compose via `stopTrackingRequested`.
    private fun handleStopTrackingIntent(intent: Intent?) {
        if (intent?.action == TrackingService.ACTION_STOP_TRACKING) {
            applicationScope.launch {
                try {
                    trackingSessionManager.discard()
                } catch (e: CancellationException) {
                    throw e
                } catch (expected: Exception) {
                    // The scope has no handler, so an uncaught failure would end the process. The screen is
                    // already on its way back to Route; the stored session is offered again by the next restore.
                    logger.debug(TAG, "Discarding the session from the notification Stop failed: $expected")
                }
            }
            stopTrackingRequested.value = true
        }
    }
}

@Composable
private fun TrailMetricsRoot(
    stopTrackingRequested: MutableState<Boolean>,
    viewModel: SavedSessionOfferViewModel = koinViewModel()
) {
    val state: SavedSessionOfferState by viewModel.state.collectAsStateWithLifecycle()
    SavedSessionOfferEvents(viewModel.events)
    TrailMetricsNavHost(
        stopTrackingRequested = stopTrackingRequested,
        savedSessionOffer = state.offer,
        onSavedSessionOfferConsumed = { viewModel.onAction(SavedSessionOfferAction.OfferConsumed) }
    )
}

@Composable
internal fun SavedSessionOfferEvents(events: Flow<SavedSessionOfferEvent>) {
    val context = LocalContext.current
    LaunchedEffect(events) {
        events.collect { event ->
            when (event) {
                SavedSessionOfferEvent.RestoreFailed ->
                    Toast.makeText(context, R.string.saved_session_restore_failed, Toast.LENGTH_LONG).show()
            }
        }
    }
}

@Composable
fun TrailMetricsNavHost(
    stopTrackingRequested: MutableState<Boolean> = mutableStateOf(false),
    savedSessionOffer: AppRoute.Tracking? = null,
    onSavedSessionOfferConsumed: () -> Unit = {}
) {
    val navController: NavHostController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = AppRoute.RoutePlanning
    ) {
        composable<AppRoute.RoutePlanning> {
            RouteScreen(
                onStartTrackingClicked = { startPoint, plannedRoutePoints, selectedActivityType ->
                    navController.navigate(
                        AppRoute.Tracking(
                            startPoint,
                            plannedRoutePoints,
                            selectedActivityType
                        )
                    )
                },
                bottomBar = { TrailMetricsBottomBar(navController) }
            )
        }

        composable<AppRoute.Tracking>(
            typeMap = mapOf(
                typeOf<Coordinates>() to CoordinatesNavType,
                typeOf<List<Coordinates>>() to PlannedRoutePointsNavType,
            ),
            enterTransition = {
                slideInHorizontally(initialOffsetX = { fullWidth -> fullWidth }) + fadeIn()
            },
            exitTransition = {
                slideOutHorizontally(targetOffsetX = { fullWidth -> -fullWidth }) + fadeOut()
            },
            popEnterTransition = {
                slideInHorizontally(initialOffsetX = { fullWidth -> -fullWidth }) + fadeIn()
            },
            popExitTransition = {
                slideOutHorizontally(targetOffsetX = { fullWidth -> fullWidth }) + fadeOut()
            }
        ) { backStackEntry ->
            val route: AppRoute.Tracking = backStackEntry.toRoute()
            TrackingScreen(
                initialStartPoint = route.startPoint,
                plannedRoutePoints = route.plannedRoutePoints,
                activityType = route.selectedActivityType,
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable<AppRoute.History> {
            HistoryScreen(
                onActivityClicked = { activityId ->
                    navController.navigate(AppRoute.ActivityDetails(activityId))
                },
                bottomBar = { TrailMetricsBottomBar(navController) }
            )
        }

        composable<AppRoute.ActivityDetails> { backStackEntry ->
            val route: AppRoute.ActivityDetails = backStackEntry.toRoute()
            DetailsScreen(
                activityId = route.activityId,
                onNavigateBack = { navController.popBackStack() }
            )
        }
    }
    // After the NavHost call, so a back stack that Android restored is already in place. Before the Stop
    // effect, which reads and resets the same flag.
    SavedSessionOfferEffect(
        navController = navController,
        offer = savedSessionOffer,
        stopTrackingRequested = stopTrackingRequested,
        onConsumed = onSavedSessionOfferConsumed
    )

    LaunchedEffect(stopTrackingRequested.value) {
        if (stopTrackingRequested.value) {
            navController.popBackStack(AppRoute.RoutePlanning, inclusive = false)
            stopTrackingRequested.value = false
        }
    }
}

/**
 * Navigates to the saved session once and consumes it. Nothing is navigated when the current destination
 * is already the Tracking screen (a back stack Android restored) or when the notification's Stop discards
 * the session in this launch; the offer is consumed all the same, so it is never navigated twice.
 */
@Composable
internal fun SavedSessionOfferEffect(
    navController: NavHostController,
    offer: AppRoute.Tracking?,
    stopTrackingRequested: MutableState<Boolean>,
    onConsumed: () -> Unit
) {
    LaunchedEffect(offer) {
        if (offer == null) return@LaunchedEffect
        val isOnTracking = navController.currentDestination?.hasRoute<AppRoute.Tracking>() == true
        if (!isOnTracking && !stopTrackingRequested.value) navController.navigate(offer)
        onConsumed()
    }
}
