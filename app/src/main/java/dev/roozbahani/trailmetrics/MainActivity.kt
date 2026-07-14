package dev.roozbahani.trailmetrics

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.feature.route.RouteScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TrailMetricsTheme {
                RouteScreen()
            }
        }
    }
}