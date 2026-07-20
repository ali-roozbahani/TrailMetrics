package dev.roozbahani.trailmetrics

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.feature.route.RouteScreen
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreen

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
        startDestination = TrailMetricsRoute.RoutePlanning
    ) {
        composable<TrailMetricsRoute.RoutePlanning> {
            RouteScreen(
                onStartTrackingClicked = { startPoint, plannedRoutePoints ->
                    navController.navigate(
                        TrailMetricsRoute.Tracking(
                            startPoint,
                            plannedRoutePoints
                        )
                    )
                }
            )
        }

        composable<TrailMetricsRoute.Tracking> { backStackEntry ->
            val route: TrailMetricsRoute.Tracking = backStackEntry.toRoute()
            TrackingScreen(
                initialStartPoint = route.startPoint,
                plannedRoutePoints = route.plannedRoutePoints
            )
        }
    }
}
