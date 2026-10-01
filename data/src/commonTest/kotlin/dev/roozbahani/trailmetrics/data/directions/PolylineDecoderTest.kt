package dev.roozbahani.trailmetrics.data.directions

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class PolylineDecoderTest {

    @Test
    fun `reference polyline decodes to its three points in order`() {
        val points = decodePolyline(PolylineFixtures.REFERENCE)

        assertEquals(PolylineFixtures.REFERENCE_POINTS, points.map { it.coordinates.latitude to it.coordinates.longitude })
        assertEquals(listOf(0, 1, 2), points.map { it.order })
    }

    @Test
    fun `empty polyline decodes to no points`() {
        assertEquals(emptyList(), decodePolyline(""))
    }

    @Test
    fun `polyline truncated mid-chunk throws IllegalArgumentException naming the index`() {
        val error = assertFailsWith<IllegalArgumentException> { decodePolyline(PolylineFixtures.TRUNCATED) }

        assertTrue(error.message.orEmpty().contains("index ${PolylineFixtures.TRUNCATED.length}"), error.message)
    }

    @Test
    fun `polyline whose final character has the continuation bit set throws IllegalArgumentException naming the index`() {
        val error = assertFailsWith<IllegalArgumentException> { decodePolyline(PolylineFixtures.UNTERMINATED) }

        assertTrue(error.message.orEmpty().contains("index ${PolylineFixtures.UNTERMINATED.length}"), error.message)
    }

    @Test
    fun `polyline ending after a latitude chunk throws IllegalArgumentException naming the index`() {
        val latitudeOnly = PolylineFixtures.REFERENCE.take(5)

        val error = assertFailsWith<IllegalArgumentException> { decodePolyline(latitudeOnly) }

        assertTrue(error.message.orEmpty().contains("index 5"), error.message)
    }
}
