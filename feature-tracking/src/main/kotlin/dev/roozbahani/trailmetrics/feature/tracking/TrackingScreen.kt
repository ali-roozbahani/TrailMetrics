package dev.roozbahani.trailmetrics.feature.tracking

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.rememberCameraPositionState
import dev.roozbahani.trailmetrics.core.map.RoutePolyline
import dev.roozbahani.trailmetrics.core.map.TrailGoogleMap
import org.koin.androidx.compose.koinViewModel

@Composable
fun TrackingScreen(
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
            viewModel.onLocationPermissionGranted()
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
                uiState.currentPath.takeIf { it.isNotEmpty() }?.let { points ->
                    RoutePolyline(points = points)
                }
            }
        }
    }
}
