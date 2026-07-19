package dev.roozbahani.trailmetrics.core.map

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.Polyline
import dev.roozbahani.trailmetrics.domain.model.Coordinates

@Composable
fun RoutePolyline(points: List<Coordinates>, color: Color = MaterialTheme.colorScheme.primary) {
    Polyline(
        points = remember(points) { points.map { LatLng(it.latitude, it.longitude) } },
        color = color,
        width = 8f
    )
}
