package dev.roozbahani.trailmetrics.feature.history

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.rememberCameraPositionState
import dev.roozbahani.trailmetrics.core.designsystem.component.MetricCell
import dev.roozbahani.trailmetrics.core.map.RoutePolyline
import dev.roozbahani.trailmetrics.core.map.StartFinishMarker
import dev.roozbahani.trailmetrics.core.map.TrailGoogleMap
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.util.formatCalories
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import dev.roozbahani.trailmetrics.domain.util.formatElapsedTime
import dev.roozbahani.trailmetrics.domain.util.formatSpeed
import org.koin.androidx.compose.koinViewModel
import org.koin.core.parameter.parametersOf

@Composable
fun DetailsScreen(
    activityId: Long,
    viewModel: DetailsViewModel = koinViewModel(parameters = { parametersOf(activityId) })
) {
    val uiState: DetailsUiState by viewModel.uiState.collectAsStateWithLifecycle()
    val activity = uiState.activity

    Scaffold { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            when {
                uiState.isLoading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }

                activity != null -> {
                    ActivityDetailsContent(activity = activity)
                }

                else -> {
                    Text(
                        text = stringResource(R.string.msg_activity_not_found)
                    )
                }
            }
        }
    }
}

@Composable
private fun ActivityDetailsContent(activity: ActivityRecord) {
    val cameraPositionState = rememberCameraPositionState()

    LaunchedEffect(activity.actualPath) {
        val boundsPoints = activity.actualPath.ifEmpty { activity.plannedRoutePoints }
        if (boundsPoints.isNotEmpty()) {
            val bounds = LatLngBounds.builder().apply {
                boundsPoints.forEach { include(LatLng(it.latitude, it.longitude)) }
            }.build()
            cameraPositionState.position =
                CameraPosition.fromLatLngZoom(bounds.center, DEFAULT_ZOOM)
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        TrailGoogleMap(
            cameraPositionState = cameraPositionState,
            modifier = Modifier
                .fillMaxWidth()
                .height(280.dp)
        ) {
            if (activity.plannedRoutePoints.isNotEmpty()) {
                RoutePolyline(
                    points = activity.plannedRoutePoints,
                    color = MaterialTheme.colorScheme.outlineVariant
                )
            }
            if (activity.actualPath.isNotEmpty()) {
                RoutePolyline(
                    points = activity.actualPath,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            val startPoint = activity.plannedRoutePoints.firstOrNull()
                ?: activity.actualPath.firstOrNull()
            startPoint?.let {
                StartFinishMarker(
                    coordinates = it,
                    title = stringResource(CoreStrings.marker_title_start_finish)
                )
            }
        }

        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row {
                    MetricCell(
                        icon = Icons.Filled.Route,
                        label = stringResource(CoreStrings.label_distance),
                        value = formatDistance(activity.distanceMeters),
                        modifier = Modifier.weight(1f)
                    )
                    MetricCell(
                        icon = Icons.Filled.Timer,
                        label = stringResource(CoreStrings.label_duration),
                        value = formatElapsedTime(activity.durationMillis),
                        modifier = Modifier.weight(1f)
                    )
                }
                Row(modifier = Modifier.padding(top = 16.dp)) {
                    MetricCell(
                        icon = Icons.Filled.Speed,
                        label = stringResource(CoreStrings.label_average_speed),
                        value = formatSpeed(activity.averageSpeedMetersPerSecond),
                        modifier = Modifier.weight(1f)
                    )
                    MetricCell(
                        icon = Icons.Filled.LocalFireDepartment,
                        label = stringResource(CoreStrings.label_calories),
                        value = formatCalories(activity.calories),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

private const val DEFAULT_ZOOM = 15f
