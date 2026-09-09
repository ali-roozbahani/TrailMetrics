package dev.roozbahani.trailmetrics.core.map

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.CameraPositionState
import com.google.maps.android.compose.GoogleMap

@Composable
fun TrailGoogleMap(
    cameraPositionState: CameraPositionState,
    modifier: Modifier = Modifier,
    onMapLongClicked: ((LatLng) -> Unit)? = null,
    content: @Composable () -> Unit
) {
    GoogleMap(
        modifier = modifier.fillMaxSize(),
        cameraPositionState = cameraPositionState,
        onMapLongClick = { latLng -> onMapLongClicked?.invoke(latLng) }
    ) {
        content()
    }
}
