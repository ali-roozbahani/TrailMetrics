package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RoutePoint

/**
 * Decodes a Google encoded polyline.
 *
 * @throws IllegalArgumentException if the input ends in the middle of a coordinate
 * (truncated, or its final character still has the continuation bit set).
 */
fun decodePolyline(encoded: String): List<RoutePoint> {
    val points = mutableListOf<RoutePoint>()
    var index = 0
    var lat = 0
    var lng = 0

    while (index < encoded.length) {
        val deltaLat = decodeValue(encoded, index)
        index = deltaLat.nextIndex
        lat += deltaLat.value

        val deltaLng = decodeValue(encoded, index)
        index = deltaLng.nextIndex
        lng += deltaLng.value

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

private class DecodedValue(val value: Int, val nextIndex: Int)

private fun decodeValue(encoded: String, startIndex: Int): DecodedValue {
    var index = startIndex
    var shift = 0
    var result = 0
    var byte: Int
    do {
        require(index < encoded.length) { "Malformed polyline: truncated at index $index" }
        byte = encoded[index++].code - 63
        result = result or ((byte and 0x1f) shl shift)
        shift += 5
    } while (byte >= 0x20)
    val value = if (result and 1 != 0) (result shr 1).inv() else (result shr 1)
    return DecodedValue(value, index)
}
