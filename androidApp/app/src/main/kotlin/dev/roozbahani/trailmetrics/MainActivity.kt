package dev.roozbahani.trailmetrics

import android.content.Intent
import android.os.Bundle
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
import androidx.compose.runtime.mutableStateOf
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.core.navigation.AppRoute
import dev.roozbahani.trailmetrics.data.tracking.TrackingService
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.feature.history.DetailsScreen
import dev.roozbahani.trailmetrics.feature.history.HistoryScreen
import dev.roozbahani.trailmetrics.feature.route.RouteScreen
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreen
import dev.roozbahani.trailmetrics.navigation.CoordinatesNavType
import dev.roozbahani.trailmetrics.navigation.PlannedRoutePointsNavType
import dev.roozbahani.trailmetrics.navigation.TrailMetricsBottomBar
import kotlin.reflect.typeOf
import org.koin.android.ext.android.inject

class MainActivity : ComponentActivity() {

    private val trackingSessionManager: TrackingSessionManager by inject()

    // Set when the tracking notification's Stop action launches/resumes this Activity —
    // read once by TrailMetricsNavHost to pop back to Route, matching what tapping Stop
    // inside TrackingScreen already does.
    private val stopTrackingRequested: MutableState<Boolean> = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleStopTrackingIntent(intent)
        setContent {
            TrailMetricsTheme {
                TrailMetricsNavHost(stopTrackingRequested = stopTrackingRequested)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleStopTrackingIntent(intent)
    }

    // Stopping the session doesn't need Compose, so it happens immediately here rather
    // than being deferred into the LaunchedEffect below — matching how promptly the
    // previous Service-targeted PendingIntent stopped it. Only the resulting navigation
    // (which needs the NavHostController) is deferred into Compose via
    // `stopTrackingRequested`.
    private fun handleStopTrackingIntent(intent: Intent?) {
        if (intent?.action == TrackingService.ACTION_STOP_TRACKING) {
            trackingSessionManager.stop()
            stopTrackingRequested.value = true
        }
    }
}

@Composable
fun TrailMetricsNavHost(stopTrackingRequested: MutableState<Boolean> = mutableStateOf(false)) {
    val navController: NavHostController = rememberNavController()

    LaunchedEffect(stopTrackingRequested.value) {
        if (stopTrackingRequested.value) {
            navController.popBackStack(AppRoute.RoutePlanning, inclusive = false)
            stopTrackingRequested.value = false
        }
    }

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
}
