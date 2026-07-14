package dev.roozbahani.trailmetrics.feature.route

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.rememberCameraPositionState
import com.google.maps.android.compose.rememberUpdatedMarkerState
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import org.koin.androidx.compose.koinViewModel

@Composable
fun RouteScreen(
    viewModel: RouteViewModel = koinViewModel()
) {
    val uiState: RouteUiState by viewModel.uiState.collectAsStateWithLifecycle()
    val cameraPositionState = rememberCameraPositionState()
    val snackBarHostState = remember { SnackbarHostState() }
    val hapticFeedback = LocalHapticFeedback.current
    val context = LocalContext.current

    @Suppress("LocalContextGetResourceValueCall")
    LaunchedEffect(Unit) {
        viewModel.uiEvents.collect { event ->
            when (event) {
                is RouteUiEvent.ShowError -> {
                    snackBarHostState.showSnackbar(context.getString(event.error.errorResId))
                }

                is RouteUiEvent.RequestLocationPermission -> {
                    // TODO: launcher.launch(...)
                }
            }
        }
    }

    LaunchedEffect(uiState.startPoint) {
        uiState.startPoint?.let { coordinates ->
            cameraPositionState.position = CameraPosition.fromLatLngZoom(
                LatLng(coordinates.latitude, coordinates.longitude),
                DEFAULT_ZOOM
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
            GoogleMap(
                modifier = Modifier.fillMaxSize(),
                cameraPositionState = cameraPositionState,
                onMapLongClick = { latLng ->
                    hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                    viewModel.onMapTapped(
                        Coordinates(latitude = latLng.latitude, longitude = latLng.longitude)
                    )
                }
            ) {
                uiState.waypoints.forEach { point ->
                    Marker(
                        state = rememberUpdatedMarkerState(
                            position = LatLng(
                                point.coordinates.latitude,
                                point.coordinates.longitude
                            )
                        )
                    )
                }
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Button(
                    onClick = { viewModel.onGenerateRouteClicked() },
                    enabled = uiState.canGenerateRoute
                ) {
                    if (uiState.isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text(stringResource(R.string.btn_generate_route))
                    }
                }
            }
        }
    }

}

private const val DEFAULT_ZOOM = 15f
