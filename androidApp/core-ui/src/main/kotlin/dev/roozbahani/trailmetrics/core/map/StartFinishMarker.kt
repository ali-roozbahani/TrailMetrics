package dev.roozbahani.trailmetrics.core.map

import androidx.compose.runtime.Composable
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.rememberUpdatedMarkerState
import dev.roozbahani.trailmetrics.domain.model.Coordinates

@Composable
fun StartFinishMarker(coordinates: Coordinates, title: String) {
    Marker(
        state = rememberUpdatedMarkerState(
            position = LatLng(
                coordinates.latitude,
                coordinates.longitude
            )
        ),
        title = title,
        icon = BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN)
    )
}
