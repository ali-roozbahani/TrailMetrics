package dev.roozbahani.trailmetrics

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.core.navigation.AppRoute
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.feature.history.DetailsScreen
import dev.roozbahani.trailmetrics.feature.history.HistoryScreen
import dev.roozbahani.trailmetrics.feature.route.RouteScreen
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreen
import dev.roozbahani.trailmetrics.navigation.CoordinatesNavType
import dev.roozbahani.trailmetrics.navigation.PlannedRoutePointsNavType
import dev.roozbahani.trailmetrics.navigation.TrailMetricsBottomBar
import kotlin.reflect.typeOf

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TrailMetricsTheme {
                TrailMetricsNavHost()
            }
        }
    }
}

@Composable
fun TrailMetricsNavHost() {
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
            DetailsScreen(activityId = route.activityId)
        }
    }
}
