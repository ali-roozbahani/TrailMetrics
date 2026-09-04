package dev.roozbahani.trailmetrics.domain.util

import com.google.common.truth.Truth.assertThat
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import org.junit.Test

class CoordinatesDistanceToTest {

    @Test
    fun `distance between same point is zero`() {
        val from = Coordinates(51.33698699962992, 12.386805594469173)
        val to = Coordinates(51.33698699962992, 12.386805594469173)

        val distanceMeters = from.distanceTo(to)
        assertThat(distanceMeters).isWithin(1.0).of(0.0)
    }

    @Test
    fun `distance between two known points matches expected value`() {
        val from = Coordinates(51.33698699962992, 12.386805594469173)
        val to = Coordinates(51.419068397323194, 12.233677843156558)

        val distanceMeters = from.distanceTo(to)
        val expectedValue: Double = 14010.0
        val delta = 42.03

        assertThat(distanceMeters).isWithin(delta).of(expectedValue)
    }

    @Test
    fun `distance is symmetric regardless of direction`() {
        val p1 = Coordinates(51.33698699962992, 12.386805594469173)
        val p2 = Coordinates(51.419068397323194, 12.233677843156558)

        val distanceMetersFromP1ToP2 = p1.distanceTo(p2)
        val distanceMetersFromP2ToP1 = p2.distanceTo(p1)

        assertThat(distanceMetersFromP1ToP2).isWithin(0.0001).of(distanceMetersFromP2ToP1)
    }
}
