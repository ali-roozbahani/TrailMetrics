package dev.roozbahani.trailmetrics.feature.route

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.rememberCameraPositionState
import org.koin.androidx.compose.koinViewModel

@Composable
fun RouteScreen(
    viewModel: RouteViewModel = koinViewModel()
) {
    val uiState: RouteUiState by viewModel.uiState.collectAsStateWithLifecycle()
    val cameraPositionState = rememberCameraPositionState()

    LaunchedEffect(uiState.startPoint) {
        uiState.startPoint?.let { coordinates ->
            cameraPositionState.position = CameraPosition.fromLatLngZoom(
                LatLng(coordinates.latitude, coordinates.longitude),
                DEFAULT_ZOOM
            )
        }
    }

    GoogleMap(
        modifier = Modifier.fillMaxSize(),
        cameraPositionState = cameraPositionState
    )
}

private const val DEFAULT_ZOOM = 15f
