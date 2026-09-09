package dev.roozbahani.trailmetrics.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import dev.roozbahani.trailmetrics.R
import dev.roozbahani.trailmetrics.core.navigation.AppRoute

@Composable
fun TrailMetricsBottomBar(navController: NavHostController) {
    val navBackStackEntry: NavBackStackEntry? by navController.currentBackStackEntryAsState()
    val currentDestination: NavDestination? = navBackStackEntry?.destination

    NavigationBar {
        NavigationBarItem(
            selected = currentDestination.isRouteSelected<AppRoute.RoutePlanning>(),
            onClick = {
                navController.navigate(AppRoute.RoutePlanning) {
                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                    launchSingleTop = true
                    restoreState = true
                }
            },
            icon = { Icon(Icons.Filled.Map, contentDescription = null) },
            label = { Text(stringResource(R.string.tab_route)) }
        )
        NavigationBarItem(
            selected = currentDestination.isRouteSelected<AppRoute.History>(),
            onClick = {
                navController.navigate(AppRoute.History) {
                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                    launchSingleTop = true
                    restoreState = true
                }
            },
            icon = { Icon(Icons.Filled.History, contentDescription = null) },
            label = { Text(stringResource(R.string.tab_history)) }
        )
    }
}

private inline fun <reified T : AppRoute> NavDestination?.isRouteSelected(): Boolean =
    this?.hierarchy?.any { it.hasRoute<T>() } == true
