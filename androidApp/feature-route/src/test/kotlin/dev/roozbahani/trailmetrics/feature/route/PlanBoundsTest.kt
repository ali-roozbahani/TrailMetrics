package dev.roozbahani.trailmetrics.feature.route

import com.google.android.gms.maps.model.LatLng
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** What the camera fit of a restored plan shows: every point of the plan, and no more. */
class PlanBoundsTest {

    @Test
    fun `the bounds hold every point of the plan and touch the outermost ones`() {
        val points = listOf(
            Coordinates(52.52, 13.405),
            Coordinates(52.53, 13.39),
            Coordinates(52.51, 13.42),
            Coordinates(52.525, 13.41),
        )

        val bounds = planBounds(points)

        points.forEach { assertTrue(bounds.contains(LatLng(it.latitude, it.longitude)), "$it is outside") }
        assertEquals(LatLng(52.51, 13.39), bounds.southwest)
        assertEquals(LatLng(52.53, 13.42), bounds.northeast)
    }
}
