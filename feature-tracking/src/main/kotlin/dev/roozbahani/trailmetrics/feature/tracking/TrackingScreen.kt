package dev.roozbahani.trailmetrics.feature.tracking

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.rememberCameraPositionState
import dev.roozbahani.trailmetrics.core.map.CurrentLocationMarker
import dev.roozbahani.trailmetrics.core.map.RoutePolyline
import dev.roozbahani.trailmetrics.core.map.TrailGoogleMap
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.calculateRouteProgress
import dev.roozbahani.trailmetrics.domain.util.formatDistance
import dev.roozbahani.trailmetrics.domain.util.formatElapsedTime
import org.koin.androidx.compose.koinViewModel

@Composable
fun TrackingScreen(
    initialStartPoint: Coordinates,
    plannedRoutePoints: List<Coordinates>,
    viewModel: TrackingViewModel = koinViewModel()
) {
    val uiState: TrackingUiState by viewModel.uiState.collectAsStateWithLifecycle()
    val cameraPositionState = rememberCameraPositionState()
    val snackBarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    val permissionHandler = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions.values.any { granted -> granted }
        if (granted) {
            viewModel.onLocationPermissionGranted(initialStartPoint)
        }
    }

    @Suppress("LocalContextGetResourceValueCall")
    LaunchedEffect(Unit) {
        viewModel.uiEvents.collect { event ->
            when (event) {
                is TrackingUiEvent.ShowError -> {
                    snackBarHostState.showSnackbar(context.getString(event.error.errorResId))
                }

                is TrackingUiEvent.RequestLocationPermission -> {
                    permissionHandler.launch(
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION
                        )
                    )
                }
            }
        }
    }

    LaunchedEffect(uiState.currentPath) {
        uiState.currentPath.lastOrNull()?.let { coordinates ->
            cameraPositionState.animate(
                CameraUpdateFactory.newLatLng(LatLng(coordinates.latitude, coordinates.longitude))
            )
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackBarHostState) }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            TrailGoogleMap(cameraPositionState = cameraPositionState) {
                val currentLocation = uiState.currentPath.lastOrNull()

                val progress = remember(currentLocation) {
                    currentLocation?.let { calculateRouteProgress(plannedRoutePoints, it) }
                }

                progress?.remainingSegment?.let { remaining ->
                    RoutePolyline(points = remaining, color = MaterialTheme.colorScheme.outlineVariant)
                }
                progress?.traveledSegment?.let { traveled ->
                    RoutePolyline(points = traveled, color = MaterialTheme.colorScheme.primary)
                }

                currentLocation?.let { CurrentLocationMarker(coordinates = it) }
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                uiState.currentMetrics?.let { metrics ->
                    MetricsDisplay(metrics = metrics)
                    Spacer(modifier = Modifier.height(16.dp))
                }

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (uiState.canStart) {
                        Button(onClick = {
                            if (hasLocationPermission(context)) {
                                viewModel.onStartClicked(initialStartPoint)
                            } else {
                                permissionHandler.launch(
                                    arrayOf(
                                        Manifest.permission.ACCESS_FINE_LOCATION,
                                        Manifest.permission.ACCESS_COARSE_LOCATION
                                    )
                                )
                            }
                        }) {
                            Text(stringResource(R.string.btn_tracking_start))
                        }
                    }
                    if (uiState.canPause) {
                        Button(onClick = viewModel::onPauseClicked) { Text(stringResource(R.string.btn_tracking_pause)) }
                    }
                    if (uiState.canResume) {
                        Button(onClick = viewModel::onResumeClicked) { Text(stringResource(R.string.btn_tracking_resume)) }
                    }
                    if (uiState.canStop) {
                        Button(onClick = viewModel::onStopClicked) { Text(stringResource(R.string.btn_tracking_stop)) }
                    }
                }
            }
        }
    }
}

@Composable
fun MetricsDisplay(
    metrics: TrackingMetrics,
    modifier: Modifier = Modifier
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
    ) {
        Text(
            text = formatDistance(metrics.distanceMeters),
            style = MaterialTheme.typography.headlineMedium
        )
        Text(
            text = formatElapsedTime(metrics.elapsedMillis),
            style = MaterialTheme.typography.bodyLarge
        )
    }
}

private fun hasLocationPermission(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
        context, Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
}
