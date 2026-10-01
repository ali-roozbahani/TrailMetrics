package dev.roozbahani.trailmetrics.data.directions

import dev.roozbahani.trailmetrics.data.common.networkJson
import kotlinx.serialization.SerializationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class DirectionsResponseDtoTest {

    private fun decode(json: String): DirectionsResponseDto = networkJson.decodeFromString(json)

    @Test
    fun `full Directions response parses status polyline and leg distances`() {
        val dto = decode(DirectionsResponseFixtures.FULL_RESPONSE)

        assertEquals("OK", dto.status)
        assertEquals(1, dto.routes.size)
        assertEquals(PolylineFixtures.REFERENCE, dto.routes[0].overviewPolyline.points)
        assertEquals(listOf(1200, 800), dto.routes[0].legs.map { it.distance.value })
    }

    @Test
    fun `unknown keys are ignored`() {
        val json = """
            {
              "geocoded_waypoints": [{ "geocoder_status": "OK" }],
              "status": "OK",
              "routes": [
                {
                  "summary": "Loop",
                  "overview_polyline": { "points": "abc", "levels": "x" },
                  "legs": [{ "distance": { "text": "1 km", "value": 1000 }, "duration": { "value": 60 } }]
                }
              ]
            }
        """.trimIndent()

        val dto = decode(json)

        assertEquals(
            DirectionsResponseDto(
                status = "OK",
                routes = listOf(RouteDto(OverviewPolylineDto("abc"), listOf(LegDto(DistanceDto(1000))))),
            ),
            dto,
        )
    }

    @Test
    fun `missing routes defaults to an empty list`() {
        val dto = decode("""{"status":"ZERO_RESULTS"}""")

        assertEquals(emptyList(), dto.routes)
    }

    @Test
    fun `route without overview_polyline fails with SerializationException`() {
        assertFailsWith<SerializationException> {
            decode("""{"status":"OK","routes":[{"legs":[{"distance":{"value":1000}}]}]}""")
        }
    }

    @Test
    fun `route without legs fails with SerializationException`() {
        assertFailsWith<SerializationException> {
            decode("""{"status":"OK","routes":[{"overview_polyline":{"points":"abc"}}]}""")
        }
    }
}
