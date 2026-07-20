package dev.roozbahani.trailmetrics.core.map

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.MarkerComposable
import com.google.maps.android.compose.rememberUpdatedMarkerState
import dev.roozbahani.trailmetrics.domain.model.Coordinates

@Composable
fun CurrentLocationMarker(coordinates: Coordinates) {
    MarkerComposable(
        state = rememberUpdatedMarkerState(
            position = LatLng(coordinates.latitude, coordinates.longitude)
        ),
        anchor = Offset(0.5f, 0.5f)
    ) {
        Box(
            modifier = Modifier
                .size(20.dp)
                .background(MaterialTheme.colorScheme.primary, CircleShape)
                .border(3.dp, Color.White, CircleShape)
        )
    }
}