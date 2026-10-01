package dev.roozbahani.trailmetrics.data.directions

// JSON bodies shaped like the Directions API response that DirectionsResponseDto reads.
object DirectionsResponseFixtures {

    fun route(polyline: String, legDistances: List<Int> = listOf(1000)): String {
        val legs = legDistances.joinToString(",") { """{"distance":{"text":"$it m","value":$it}}""" }
        return """{"overview_polyline":{"points":"$polyline"},"legs":[$legs]}"""
    }

    fun response(status: String = "OK", routes: List<String>): String =
        """{"status":"$status","routes":[${routes.joinToString(",")}]}"""

    // A realistic, trimmed Directions API response: fields the DTO does not declare are kept so
    // the tests show they are ignored.
    val FULL_RESPONSE = """
        {
          "geocoded_waypoints": [
            { "geocoder_status": "OK", "place_id": "ChIJ7cv00DwsDogRAMDACa2m4K8", "types": ["locality", "political"] }
          ],
          "routes": [
            {
              "bounds": {
                "northeast": { "lat": 43.252, "lng": -120.2 },
                "southwest": { "lat": 38.5, "lng": -126.453 }
              },
              "copyrights": "Map data ©2026",
              "legs": [
                {
                  "distance": { "text": "1.2 km", "value": 1200 },
                  "duration": { "text": "15 mins", "value": 900 },
                  "end_address": "B",
                  "start_address": "A",
                  "steps": [],
                  "traffic_speed_entry": [],
                  "via_waypoint": []
                },
                {
                  "distance": { "text": "0.8 km", "value": 800 },
                  "duration": { "text": "10 mins", "value": 600 },
                  "end_address": "A",
                  "start_address": "B",
                  "steps": [],
                  "traffic_speed_entry": [],
                  "via_waypoint": []
                }
              ],
              "overview_polyline": { "points": "${PolylineFixtures.REFERENCE}" },
              "summary": "Loop",
              "warnings": ["Walking directions are in beta."],
              "waypoint_order": [0]
            }
          ],
          "status": "OK"
        }
    """.trimIndent()
}
