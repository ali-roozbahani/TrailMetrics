package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlin.test.Test
import kotlin.test.assertEquals

class CoordinatesDistanceToTest {

    @Test
    fun `distance between same point is zero`() {
        val from = Coordinates(51.33698699962992, 12.386805594469173)
        val to = Coordinates(51.33698699962992, 12.386805594469173)

        val distanceMeters = from.distanceTo(to)
        assertEquals(expected = 0.0, actual = distanceMeters, absoluteTolerance = 1.0)
    }

    @Test
    fun `distance between two known points matches expected value`() {
        val from = Coordinates(51.33698699962992, 12.386805594469173)
        val to = Coordinates(51.419068397323194, 12.233677843156558)

        val distanceMeters = from.distanceTo(to)
        val expectedValue: Double = 14010.0
        val delta = 42.03

        assertEquals(expected = expectedValue, actual = distanceMeters, absoluteTolerance = delta)
    }

    @Test
    fun `distance is symmetric regardless of direction`() {
        val p1 = Coordinates(51.33698699962992, 12.386805594469173)
        val p2 = Coordinates(51.419068397323194, 12.233677843156558)

        val distanceMetersFromP1ToP2 = p1.distanceTo(p2)
        val distanceMetersFromP2ToP1 = p2.distanceTo(p1)

        assertEquals(expected = distanceMetersFromP2ToP1, actual = distanceMetersFromP1ToP2, absoluteTolerance = 0.0001)
    }
}
