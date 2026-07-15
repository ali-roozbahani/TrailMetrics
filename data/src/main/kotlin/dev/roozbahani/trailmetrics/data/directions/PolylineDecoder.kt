package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RoutePoint

fun decodePolyline(encoded: String): List<RoutePoint> {
    val points = mutableListOf<RoutePoint>()
    var index = 0
    var lat = 0
    var lng = 0

    while (index < encoded.length) {
        var shift = 0
        var result = 0
        var byte: Int
        do {
            byte = encoded[index++].code - 63
            result = result or ((byte and 0x1f) shl shift)
            shift += 5
        } while (byte >= 0x20)
        val deltaLat = if (result and 1 != 0) (result shr 1).inv() else (result shr 1)
        lat += deltaLat

        shift = 0
        result = 0
        do {
            byte = encoded[index++].code - 63
            result = result or ((byte and 0x1f) shl shift)
            shift += 5
        } while (byte >= 0x20)
        val deltaLng = if (result and 1 != 0) (result shr 1).inv() else (result shr 1)
        lng += deltaLng

        points.add(
            RoutePoint(
                coordinates = Coordinates(
                    latitude = lat / 1E5,
                    longitude = lng / 1E5
                ),
                order = points.size
            )
        )
    }

    return points
}
